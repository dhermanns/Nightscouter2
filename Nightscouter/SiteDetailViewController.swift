//
//  ViewController.swift
//  Nightscout
//
//  Created by Peter Ina on 5/14/15.
//  Copyright (c) 2015 Peter Ina. All rights reserved.
//

import UIKit
import NightscouterKit

class SiteDetailViewController: UIViewController, UIWebViewDelegate {
    
    // MARK: IBOutlets
    @IBOutlet weak var siteCompassControl: CompassControl?
    @IBOutlet weak var siteLastReadingHeader: UILabel?
    @IBOutlet weak var siteLastReadingLabel: UILabel?
    @IBOutlet weak var siteBatteryHeader: UILabel?
    @IBOutlet weak var siteBatteryLabel: UILabel?
    @IBOutlet weak var siteRawHeader: UILabel?
    @IBOutlet weak var siteRawLabel: UILabel?
    @IBOutlet weak var siteNameLabel: UILabel?
    @IBOutlet weak var siteWebView: UIWebView?
    @IBOutlet weak var siteActivityView: UIActivityIndicatorView?
    
    // MARK: Properties
    var site: Site? {
        didSet {
            if (site != nil){
                configureView()
            }
        }
    }
    //var nsApi: NightscoutAPIClient?
    var data = [AnyObject]()
    
    // MARK: View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // remove any uneeded decorations from this view if contained within a UI page view controller
        if let _ = parentViewController as? UIPageViewController {
            // println("contained in UIPageViewController")
            self.view.backgroundColor = UIColor.clearColor()
            self.siteNameLabel?.removeFromSuperview()
        }
        
        configureView()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
        //nsApi?.task?.cancel()
        data.removeAll()
    }
    
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        self.siteWebView?.reload()
    }
    
    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return UIStatusBarStyle.LightContent
    }
}

extension SiteDetailViewController{
    @IBAction func unwindToSiteDetail(segue:UIStoryboardSegue) {
        // print(">>> Entering \(__FUNCTION__) <<<")
        // print("\(segue)")
    }
    @IBAction func launchSiteSettings(sender: UIBarButtonItem) {
     presentSettings(sender)
    }
}

// MARK: WebKit WebView Delegates
extension SiteDetailViewController {
    func webViewDidFinishLoad(webView: UIWebView) {
        // print(">>> Entering \(__FUNCTION__) <<<")
        let updateData = "updateData(\(self.data))"
        
        if let configuration = site?.configuration {
            let updateUnits = "updateUnits(\(configuration.displayUnits.hashValue))"
            webView.stringByEvaluatingJavaScriptFromString(updateUnits)
        }
        webView.stringByEvaluatingJavaScriptFromString(updateData)
        webView.hidden = false
    }
    
}

extension SiteDetailViewController {
    
    func configureView() {
        if let site = site, dataSource = SiteSummaryModelViewModel(withSite: site) {
            siteLastReadingLabel?.text = dataSource.lastReadingLabel
            siteLastReadingLabel?.textColor = dataSource.batteryColor
            
            siteBatteryLabel?.text = dataSource.batteryLabel
            siteBatteryLabel?.textColor = dataSource.batteryColor
            
            siteRawLabel?.hidden = dataSource.rawHidden
            siteRawHeader?.hidden = dataSource.rawHidden
            
            siteRawLabel?.text = dataSource.rawLabel
            siteRawLabel?.textColor = dataSource.batteryColor
    
            siteNameLabel?.text = dataSource.nameLabel
            siteCompassControl?.configure(withDataSource: dataSource, delegate: dataSource)
        }
        
    }
    
    func updateTitles(title: String) {
        self.navigationItem.title = title
        self.navigationController?.navigationItem.title = title
        self.siteNameLabel?.text = title
    }
    
    func loadWebView () {
        self.siteWebView?.delegate = self
        self.siteWebView?.scrollView.bounces = false
        self.siteWebView?.scrollView.scrollEnabled = false
        
        let filePath = NSBundle.mainBundle().pathForResource("index", ofType: "html", inDirectory: "html")
        let defaultDBPath = "\(NSBundle.mainBundle().resourcePath)\\html"
        
        let fileExists = NSFileManager.defaultManager().fileExistsAtPath(filePath!)
        if !fileExists {
            do {
                try NSFileManager.defaultManager().copyItemAtPath(defaultDBPath, toPath: filePath!)
            } catch _ {
            }
        }
        let request = NSURLRequest(URL: NSURL.fileURLWithPath(filePath!))
        self.siteWebView?.loadRequest(request)
    }
    
    func updateScreenOverride(shouldOverride: Bool) {
        if let site = self.site {
            //            site.overrideScreenLock = shouldOverride
            
            
            //            AppDataManageriOS.sharedInstance.shouldDisableIdleTimer = site.overrideScreenLock
            //            AppDataManageriOS.sharedInstance.updateSite(site)
            UIApplication.sharedApplication().idleTimerDisabled = site.overrideScreenLock
        }
        
        #if DEBUG
            print("{site.overrideScreenLock:\(site?.overrideScreenLock), AppDataManageriOS.shouldDisableIdleTimer:\(AppDataManageriOS.sharedInstance.shouldDisableIdleTimer), UIApplication.idleTimerDisabled:\(UIApplication.sharedApplication().idleTimerDisabled)}")
        #endif
    }
    
    func presentSettings(sender: UIBarButtonItem) {
        
        let alertController = UIAlertController(title: LocalizedString.uiAlertScreenOverrideTitle.localized, message: LocalizedString.uiAlertScreenOverrideMessage.localized, preferredStyle: .ActionSheet)
        
        let cancelAction = UIAlertAction(title: LocalizedString.generalCancelLabel.localized, style: .Cancel) { (action) in
            #if DEBUG
                print("Canceled action: \(action)")
            #endif
        }
        alertController.addAction(cancelAction)
        
        let checkEmoji = "✓ "
        var yesString = "   "
        if site?.overrideScreenLock == true {
            yesString = checkEmoji
        }
        
        let yesAction = UIAlertAction(title: "\(yesString)\(LocalizedString.generalYesLabel.localized)", style: .Default) { (action) -> Void in
            //self.updateScreenOverride(true)
            #if DEBUG
                print("Yes action: \(action)")
            #endif
        }
        
        alertController.addAction(yesAction)
        
        alertController.preferredAction = yesAction
        
        var noString = "   "
        if (site!.overrideScreenLock == false) {
            noString = checkEmoji
        }
        
        let noAction = UIAlertAction(title: "\(noString)\(LocalizedString.generalNoLabel.localized)", style: .Destructive) { (action) -> Void in
            //self.updateScreenOverride(false)
            #if DEBUG
                print("No action: \(action)")
            #endif
        }
        alertController.addAction(noAction)
        
        alertController.view.tintColor = NightscouterAssetKit.darkNavColor
        
        self.view.window?.tintColor = nil
        
        // Resolving Incident with Identifier: 1169918A-77AC-4D15-8610-E62C1D74E386
        // Crash in UIPopoverPresentationController
        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = sender
        }
        
        self.presentViewController(alertController, animated: true) {
            #if DEBUG
                print("presentViewController: \(alertController.debugDescription)")
            #endif
        }
    }
    
}