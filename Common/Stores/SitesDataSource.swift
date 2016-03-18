//
//  SitesDataSource.swift
//  Nightscouter
//
//  Created by Peter Ina on 1/15/16.
//  Copyright © 2016 Nothingonline. All rights reserved.
//

import Foundation

public enum DefaultKey: String, RawRepresentable {
    case sites, lastViewedSiteIndex, primarySiteUUID
}

public class SitesDataSource: SiteStoreType {
    // MARK: Persistence
    
    public static let sharedInstance = SitesDataSource()
    
    private init() {
        self.defaults = NSUserDefaults(suiteName: AppConfiguration.sharedApplicationGroupSuiteName ) ?? NSUserDefaults.standardUserDefaults()
        
        let sessionManager = WatchSessionManager.sharedManager
        self.sessionManager = sessionManager
        self.sessionManager.store = self
        self.sessionManager.startSession()
        
        #if os(watchOS)
            self.sessionManager.requestCompanionAppUpdate()
        #endif
    }
    
    private let defaults: NSUserDefaults
    
    private let sessionManager: SessionManagerType
    
    public var storageLocation: StorageLocation { return .LocalKeyValueStore }
    
    public var sites: [Site] {
        if let loaded = loadData() {
            return loaded
        }
        return []
    }
    
    public var lastViewedSiteIndex: Int {
        get {
            return defaults.integerForKey(DefaultKey.lastViewedSiteIndex.rawValue)
        }
        set {
            if lastViewedSiteIndex != newValue {
                // defaults.setInteger(newValue, forKey: DefaultKey.lastViewedSiteIndex.rawValue)
                saveData([DefaultKey.lastViewedSiteIndex.rawValue: newValue])
            }
        }
    }
    
    public var primarySite: Site? {
        set{
            if let site = newValue {
                // defaults.setObject(site.uuid.UUIDString, forKey: DefaultKey.primarySiteUUID.rawValue)
                saveData([DefaultKey.primarySiteUUID.rawValue: site.uuid.UUIDString])
            }
        }
        get {
            if let uuidString = defaults.objectForKey(DefaultKey.primarySiteUUID.rawValue) as? String {
                return sites.filter { $0.uuid.UUIDString == uuidString }.first
            } else if let firstSite = sites.first {
                return firstSite
            }
            return nil
        }
    }
    
    // MARK: Array modification methods
    public func createSite(site: Site, atIndex index: Int?) -> Bool {
        var initial: [Site] = self.sites
        
        if initial.isEmpty {
            primarySite = site
        }
        
        if let index = index {
            initial.insert(site, atIndex: index)
        } else {
            initial.append(site)
        }
        
        let siteDict = initial.map { $0.encode() }
        
        saveData([DefaultKey.sites.rawValue: siteDict])
        
        return initial.contains(site)
    }
    
    public func updateSite(site: Site)  ->  Bool {
        
        var initial = sites
        
        let success = initial.insertOrUpdate(site)
        
        let siteDict = initial.map { $0.encode() }
        
        saveData([DefaultKey.sites.rawValue: siteDict])
        
        return success
    }
    
    public func deleteSite(site: Site) -> Bool {
        
        var initial = sites
        let success = initial.remove(site)
        AppConfiguration.keychain[site.uuid.UUIDString] = nil
        
        if sites.isEmpty {
            lastViewedSiteIndex = 0
            primarySite = nil
        }
        
        let siteDict = initial.map { $0.encode() }
        saveData([DefaultKey.sites.rawValue: siteDict])
        
        return success
    }
    
    public func clearAllSites() -> Bool {
        var initial = sites
        initial.removeAll()
        
        saveData([DefaultKey.sites.rawValue: []])
        
        return initial.isEmpty
    }
    
    public func handleApplicationContextPayload(payload: [String : AnyObject]) {
        
        if let sites = payload[DefaultKey.sites.rawValue] as? ArrayOfDictionaries {
            defaults.setObject(sites, forKey: DefaultKey.sites.rawValue)
        } else {
            print("No sites were found.")
        }
        
        if let lastViewedSiteIndex = payload[DefaultKey.lastViewedSiteIndex.rawValue] as? Int {
            self.lastViewedSiteIndex = lastViewedSiteIndex
        } else {
            print("No lastViewedIndex was found.")
        }
        
        if let uuidString = payload[DefaultKey.primarySiteUUID.rawValue] as? String {
            self.primarySite = sites.filter{ $0.uuid.UUIDString == uuidString }.first
        } else {
            print("No primarySiteUUID was found.")
        }
        
        if let action = payload["action"] as? String {
            print(action)
            for site in sites {
                #if os(iOS)
                    dispatch_async(dispatch_get_main_queue()) {
                        let socket = NightscoutSocketIOClient(site: site)
                        socket.fetchConfigurationData().startWithNext { racSite in
                            // if let racSite = racSite {
                            // self.updateSite(racSite)
                            // }
                        }
                        socket.fetchSocketData().observeNext { racSite in
                            self.updateSite(racSite)
                        }
                    }
                #endif
            }
        }
        
        defaults.synchronize()
        
        NSNotificationCenter.defaultCenter().postNotificationName(DataUpdatedNotification, object: nil)
    }
    
    public func loadData() -> [Site]? {
        if let sites = defaults.arrayForKey(DefaultKey.sites.rawValue) as? ArrayOfDictionaries {
            return sites.flatMap { Site.decode($0) }
        }
        
        return []
    }
    
    public func saveData(dictionary: [String: AnyObject]) -> (savedLocally: Bool, updatedApplicationContext: Bool) {
        
        var successfullSave: Bool = false
        
        for (key, object) in dictionary {
            defaults.setObject(object, forKey: key)
        }
        
        successfullSave = defaults.synchronize()
        
        var successfullAppContextUpdate = true
        do {
            try sessionManager.updateApplicationContext(dictionary)
        } catch {
            successfullAppContextUpdate = false
            print("error")
        }
        
        return (successfullSave, successfullAppContextUpdate)
    }
}