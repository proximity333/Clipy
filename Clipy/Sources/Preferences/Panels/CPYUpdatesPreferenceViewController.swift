//
//  CPYUpdatesPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Sparkle

class CPYUpdatesPreferenceViewController: NSViewController {

    // MARK: - Properties
    @IBOutlet private weak var versionTextField: NSTextField!
    @IBOutlet private weak var checkNowButton: NSButton!
    @IBOutlet private weak var lastCheckTextField: NSTextField!

    private var updaterController: SPUStandardUpdaterController? {
        (NSApp.delegate as? AppDelegate)?.updaterController
    }

    // MARK: - Initialize
    override func loadView() {
        super.loadView()
        versionTextField.stringValue = "v\(Bundle.main.appVersion ?? "")"
        // The updater is owned by the AppDelegate. SPUStandardUpdaterController is not a
        // shared singleton like SUUpdater was, so wire the button to it in code.
        if let controller = updaterController {
            checkNowButton.target = controller
            checkNowButton.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        lastCheckTextField.objectValue = updaterController?.updater.lastUpdateCheckDate
    }

}
