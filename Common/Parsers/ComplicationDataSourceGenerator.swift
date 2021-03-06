//
//  ComplicationDataSourceGenerator.swift
//  Nightscouter
//
//  Created by Peter Ina on 3/10/16.
//  Copyright © 2016 Nothingonline. All rights reserved.
//

import Foundation

public protocol ComplicationDataSourceGenerator {
    var oldestComplicationData: ComplicationTimelineEntry? { get }
    var latestComplicationData: ComplicationTimelineEntry? { get }
    var complicationUpdateInterval: NSTimeInterval { get }
    
    func generateComplicationData(forSite site: Site) -> [ComplicationTimelineEntry]
    func generateComplicationData(forConfiguration configuration: ServerConfiguration, sgvs:[SensorGlucoseValue], calibrations:[Calibration]) -> [ComplicationTimelineEntry]
    
    func nearest(calibration cals: [Calibration], forDate date: NSDate) -> Calibration?
}

public extension ComplicationDataSourceGenerator {
    var complicationUpdateInterval: NSTimeInterval { return 60.0 * 30.0 }
    
    var nextRequestedComplicationUpdateDate: NSDate {
        guard let latestComplicationData = latestComplicationData else {
            return NSDate(timeIntervalSinceNow: complicationUpdateInterval)
        }
        
        return latestComplicationData.date.dateByAddingTimeInterval(complicationUpdateInterval)
    }
    
    // MARK: Convenience methods for generating complication data.
    func generateComplicationData(forSite site: Site) -> [ComplicationTimelineEntry] {
        return generateComplicationData(forConfiguration: site.configuration ?? ServerConfiguration(), sgvs: site.sgvs, calibrations: site.cals)
    }
    
    func nearest(calibration cals: [Calibration], forDate date: NSDate) -> Calibration? {
        var desiredIndex: Int?
        var minDate: NSTimeInterval = fabs(NSDate().timeIntervalSinceNow)
        for (index, cal) in cals.enumerate() {
            let dateInterval = fabs(cal.date.timeIntervalSinceDate(date))
            let compared = minDate < dateInterval
            if compared {
                minDate = dateInterval
                desiredIndex = index
            }
        }
        guard let index = desiredIndex else {
            print("NON-FATAL ERROR: No valid index was found... return first calibration if its there.")
            return cals.first
        }
        return cals[safe: index]
    }
}

// MARK: Complication Data Source

extension Site: ComplicationDataSourceGenerator {
    
    public func generateComplicationData(forConfiguration configuration: ServerConfiguration, sgvs:[SensorGlucoseValue], calibrations:[Calibration]) -> [ComplicationTimelineEntry] {
        
        // Init Complication Model Array for return as Timeline.
        var compModels: [ComplicationTimelineEntry] = []
        
        // Get prfered Units for site.
        let units = configuration.displayUnits
        
        // Setup thresholds for proper color coding.
        let thresholds: Thresholds = configuration.settings?.thresholds ?? Thresholds(bgHigh: 300, bgLow: 70, bgTargetBottom: 60, bgTargetTop: 250)
        
        // Iterate through provided Sensor Glucose Values to create a timeline.
        for (index, sgv) in sgvs.enumerate() {
            
            // Create a color for a given SGV value.
            let sgvColor = thresholds.desiredColorState(forValue: sgv.mgdl)
            
            // Set the date required by the Complication Data Source (for Timeline)
            let date = sgv.date
            
            // Convet Sensor Glucose Value to a proper string. Always start with a mgd/L number then convert to a mmol/L
            var sgvString = sgv.mgdl.formattedForMgdl
            if units == .Mmol {
                sgvString = sgv.mgdl.formattedForMmol
            }
            
            //
            // END of Delta Calculation
            //
            // Init Delta var.
            var delta: MgdlValue = 0
            
            // Get the next index position which would be a previous or older reading.
            let previousIndex: Int = index + 1
            // If the next index is a valid object and the number is safe.
            if let previousSgv = sgvs[safe: previousIndex] where sgv.isSGVOk {
                delta = sgv.mgdl - previousSgv.mgdl
            }
            // Convert to proper units
            if units == .Mmol {
                delta = delta.toMmol
            }
            
            // Create strings if the sgv is ok. Otherwise clear it out.
            let deltaString = sgv.isSGVOk ? "(" + delta.formattedBGDelta(forUnits: units) + ")" : ""
            
            // END of Delta Calculation
            //
            
            //
            // Start of Raw Calculation
            //
            // Init Raw String var
            var rawString: String = ""
            
            // Get nearest calibration for a given sensor glucouse value's date.
            if let calibration = nearest(calibration: calibrations, forDate: sgv.date) {
                
                // Calculate Raw BG for a given calibration.
                let raw = calculateRawBG(fromSensorGlucoseValue: sgv, calibration: calibration)
                var rawFormattedString = raw.formattedForMgdl
                // Convert to correct units.
                if units == .Mmol {
                    rawFormattedString = raw.formattedForMmol
                }
                // Create string representation of raw data.
                rawString = rawFormattedString
            }
            
            let compModel = ComplicationTimelineEntry(date: date, rawLabel: rawString, nameLabel: configuration.displayName, sgvLabel: sgvString, deltaLabel: deltaString, tintColor: sgvColor.colorValue, units: units, direction: sgv.direction, noise: sgv.noise)
            
            compModels.append(compModel)
        }
        
        
        let settings = configuration.settings ?? ServerConfiguration().settings!
        
        // Get the latest model and use to create stale complication timeline entries.
        let model = compModels.maxElement{ (lModel, rModel) -> Bool in
            return rModel.date.compare(lModel.date) == .OrderedDescending
        }
        
        if let model = model {
            // take last date and extend out 15 minutes.
            if settings.timeAgo.warn {
                let warnTime = settings.timeAgo.warnMins
                let warningStaleDate = model.date.dateByAddingTimeInterval(warnTime)
                let warnItem = ComplicationTimelineEntry(date: warningStaleDate, rawLabel: "Please update.", nameLabel: "Data missing.", sgvLabel: "Warning", deltaLabel: "", tintColor: DesiredColorState.Warning.colorValue, units: .Mgdl, direction: .None, noise: .None)
                compModels.append(warnItem)
            }
            
            if settings.timeAgo.urgent {
                // take last date and extend out 30 minutes.
                let urgentTime = settings.timeAgo.urgentMins
                let urgentStaleDate = model.date.dateByAddingTimeInterval(urgentTime)
                let urgentItem = ComplicationTimelineEntry(date: urgentStaleDate, rawLabel: "Please update.", nameLabel: "Data missing.", sgvLabel: "Urgent", deltaLabel: "", tintColor: DesiredColorState.Alert.colorValue, units: .Mgdl, direction: .None, noise: .None)
                compModels.append(urgentItem)
            }
        }
        
        compModels.sortByDate()
        
        return compModels
    }
    
    public var latestComplicationData: ComplicationTimelineEntry? {
        let complicationModels: [ComplicationTimelineEntry] = self.complicationTimeline ?? []
        
        return sortByDate(complicationModels).first
    }
    
    public var oldestComplicationData: ComplicationTimelineEntry? {
        let complicationModels: [ComplicationTimelineEntry] = self.complicationTimeline ?? []
        
        return sortByDate(complicationModels).last
    }
    
}

public extension Site {
    mutating func generateTimeline() {
        self.complicationTimeline = generateComplicationData(forSite: self)
    }
}