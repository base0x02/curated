import XCTest

/// End-to-end flows against a test copy of the Mac app (see README). Screenshots go to
/// $SCREENSHOT_DIR (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild) when set.
final class CuratedUITests: XCTestCase {
    private var app: XCUIApplication!
    private var testMac: String { ProcessInfo.processInfo.environment["TEST_MAC"] ?? "127.0.0.1:18765" }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Playing Automix, then tapping a creator on Home: their list should open, and Automix keep playing.
    func test9_CreatorTapKeepsPlaying() {
        app.launchArguments = ["-muteCurated"]
        app.launch()
        sleep(4)
        shot("90-automix-playing")
        // The player's own Back, or the system's on iPhone Duo's outer display (its toolbar down the side).
        if app.buttons["Back"].exists {
            app.buttons["Back"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.896, dy: 0.286)).tap()  // The side toolbar's back chevron.
        }
        sleep(1)
        shot("91-home")
        let creator = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'creator-'")).firstMatch
        XCTAssertTrue(creator.waitForExistence(timeout: 5))
        creator.tap()
        sleep(3)
        shot("92-after-creator-tap")
    }

    /// Fresh install → pair by address and code → first sync.
    func test1_PairAndSync() {
        app.launchArguments = ["-resetCurated"]
        app.launch()
        shot("01-empty")

        // A fresh install opens on the pairing screen.
        sleep(4)  // let the Bonjour search finish
        shot("02-pair")

        app.buttons["Enter your Mac's address instead"].tap()
        let address = app.textFields["addressField"]
        address.tap()
        address.typeText(testMac)
        let code = app.textFields["codeField"]
        code.tap()
        code.typeText("123456")  // The last digit starts pairing.
        shot("03-pair-filled")

        // It syncs, then fades into the app (Automix, when there's something to watch).
        XCTAssertTrue(app.staticTexts["You're all set"].waitForExistence(timeout: 60))
        shot("04-synced")
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 10) || app.buttons["Automix"].waitForExistence(timeout: 10))
        shot("05-home")
    }

    /// Opens straight into Automix; Time Limit on and off, speed, back into the mini player, and stopping it.
    func test2_Player() {
        app.launch()
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 5), "should open into Automix")
        sleep(2)
        shot("10-automix")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Time Limit'")).firstMatch.tap()
        sleep(2)
        shot("11-time-limit")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'End the'")).firstMatch.tap()
        sleep(1)
        shot("12-time-limit-off")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Playback speed'")).firstMatch.tap()
        shot("13-speed")

        app.buttons["Queue"].tap()
        sleep(1)
        shot("14-queue")
        app.buttons["Done"].tap()

        app.buttons["Back"].tap()
        XCTAssertTrue(app.otherElements["nowPlayingBar"].waitForExistence(timeout: 5)
                      || app.buttons["Stop"].waitForExistence(timeout: 5))
        shot("15-mini-player")

        app.buttons["Stop"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Stop"].exists)
        shot("16-stopped")
    }

    /// Save a video for later, then play the Watch Later list from Home.
    func test3_WatchLater() {
        app.launch()
        XCTAssertTrue(app.buttons["Watch Later"].waitForExistence(timeout: 5))
        sleep(1)
        app.buttons["Watch Later"].tap()
        sleep(1)
        shot("17-saved-for-later")
        app.buttons["Back"].tap()
        let row = app.buttons["watchLaterRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        shot("18-home-watch-later")
        row.tap()
        // Its list pops out of the button; the first video plays the list.
        let first = app.buttons["savedListRow-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        shot("18b-watch-later-list")
        first.tap()
        sleep(2)
        shot("19-watch-later-player")
        app.buttons["Back"].tap()
    }

    /// Home's creator cards, a creator's list, and the sync screen when paired.
    func test4_CreatorsAndSync() {
        app.launch()
        if app.buttons["Back"].waitForExistence(timeout: 3) { app.buttons["Back"].tap() }
        let alice = app.buttons["creator-alice"]
        XCTAssertTrue(alice.waitForExistence(timeout: 5))
        alice.press(forDuration: 1.0)
        sleep(1)
        shot("20-mark-all-menu")
        app.buttons["Mark All as Watched"].tap()
        sleep(1)
        shot("21-home-after-mark")
        let toggle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show' AND label ENDSWITH 'caught-up creators'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        sleep(1)
        shot("22-caught-up-shown")
        app.buttons["creator-alice"].tap()
        sleep(1)
        shot("23-creator")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Settings"].tap()
        sleep(1)
        shot("24-sync-paired")
    }

    /// Playing, then leaving the app, should continue in picture in picture.
    func test5_PictureInPicture() {
        app.launch()
        if !app.buttons["Queue"].waitForExistence(timeout: 3) { app.buttons["Automix"].firstMatch.tap() }
        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(3)
        shot("30-pip-home")
        app.activate()
        sleep(2)
        shot("31-back-from-pip")
    }
}

extension CuratedUITests {
    /// Swipe-to-next: drag halfway and hold (the host takes screenshots meanwhile), then a full swipe.
    func test6_Swipe() {
        app.launch()
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 5))
        sleep(2)
        shot("40-before-swipe")
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let half = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: half, withVelocity: .slow, thenHoldForDuration: 5)
        sleep(1)
        shot("41-after-half-release")
        let top = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.05, thenDragTo: top, withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        shot("42-after-full-swipe")
    }
}

extension CuratedUITests {
    /// A short drag springs back to the same video; a swipe down brings back the previous one.
    func test7_SwipeBackAndPrevious() {
        app.launch()
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 5))
        sleep(2)
        let window = app.windows.firstMatch
        let title = { self.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Clip '")).firstMatch.label }
        let first = title()
        let low = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        low.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                  withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertEqual(title(), first, "a short drag should spring back")
        low.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                  withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        let second = title()
        XCTAssertNotEqual(second, first, "a full swipe up should move on")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        sleep(1)
        XCTAssertEqual(title(), first, "a swipe down should bring back the previous video")
        shot("43-back-to-previous")
    }
}

extension CuratedUITests {
    /// iPad: portrait is the iPhone layout, landscape the Mac's; rotating keeps the video playing.
    func test8_iPadLayouts() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        XCUIDevice.shared.orientation = .portrait
        // Pair straight with the test Mac (never the everyday one Bonjour may also find) and sync.
        app.launchArguments = ["-resetCurated"]
        app.launchEnvironment["CURATED_TEST_PAIR"] = "\(testMac):123456"
        app.launch()
        sleep(12)
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 5), "portrait opens into the full-screen player")
        sleep(2)
        shot("50-ipad-portrait-player")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.buttons["Hide Queue"].waitForExistence(timeout: 5), "landscape shows the Mac layout")
        XCTAssertTrue(app.buttons["Pause"].exists, "still playing after rotating")
        shot("51-ipad-landscape-automix")

        app.buttons["Time Limit: a 1-minute mix"].firstMatch.tap()
        sleep(1)
        shot("52-ipad-landscape-time-limit")

        app.buttons["creator-carol"].tap()
        sleep(1)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Clip'")).firstMatch.tap()
        sleep(2)
        shot("53-ipad-landscape-creator")

        app.buttons["Hide Queue"].tap()
        sleep(1)
        shot("54-ipad-landscape-queue-hidden")
        app.buttons["Show Queue"].tap()

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 5), "portrait shows the full-screen player again")
        shot("55-ipad-back-to-portrait")
    }
}

extension CuratedUITests {
    /// Holds the app in landscape for a minute so the layout can be inspected from the host.
    func test9_HoldLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        sleep(60)
    }
}

extension CuratedUITests {
    /// A long video upright: tap to show the controls, then Full Screen should turn the screen sideways with an exit.
    func test10_LongFullscreen() {
        app.launchArguments = ["-curatedLong", "-muteCurated"]
        app.launch()
        sleep(4)
        shot("40-long-upright")
        let video = app.otherElements["Video"].firstMatch
        if video.exists { video.tap() } else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap() }
        sleep(1)
        shot("41-long-controls")
        let full = app.buttons["Full Screen"].firstMatch
        print("FULL exists \(full.exists) hittable \(full.isHittable) frame \(full.frame)")
        print("PIP exists \(app.buttons["Picture in Picture"].exists)")
        if full.exists { full.tap() }
        sleep(2)
        shot("42-long-fullscreen")
        print("EXIT exists \(app.buttons["Exit Full Screen"].exists) orientation \(XCUIDevice.shared.orientation.rawValue)")
    }
}

extension CuratedUITests {
    /// Settings' Force Download, already paired with a test Mac that has creators and a finished download: the ring
    /// should show while it runs, then a checkmark that the sync it starts leaves and the next sync removes.
    func test11_ForceDownload() {
        app.launchArguments = ["-curatedSettings", "-muteCurated"]
        app.launch()
        let button = app.buttons["forceDownload"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Last Download on Mac"].waitForExistence(timeout: 20))
        button.tap()
        let ring = app.descendants(matching: .any)["macDownloadProgress"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        shot("50-force-download-running")
        let done = app.descendants(matching: .any)["macDownloadDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 90))
        XCTAssertFalse(ring.exists)
        sleep(4)  // The sync it starts has run by now, with nothing to fetch.
        XCTAssertTrue(done.exists)
        shot("51-force-download-done")
        app.buttons["syncNow"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: done)], timeout: 20)
        shot("52-force-download-synced")
    }

    /// Settings fills the screen: tabs on an upright iPhone, the pages on the left otherwise. Turning keeps the page,
    /// and Done closes it. Needs a pairing (seed pairing.json), so the app doesn't open on the pairing screen.
    func test12_SettingsLayouts() {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        app.launchArguments = ["-curatedSettings", "-muteCurated", "-curatedHome"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["settingsDone"].firstMatch.waitForExistence(timeout: 15))
        if pad {
            XCTAssertTrue(app.buttons["settings-storage"].exists, "an iPad lists the pages upright too")
            app.buttons["settings-storage"].tap()
        } else {
            XCTAssertFalse(app.buttons["settings-storage"].exists, "an upright iPhone has tabs")
            app.tabBars.buttons["Storage"].tap()
        }
        XCTAssertTrue(app.staticTexts["Watch time"].waitForExistence(timeout: 5))
        shot("60-settings-upright")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["settings-storage"].waitForExistence(timeout: 5), "sideways lists the pages")
        shot("60b-settings-turned")
        XCTAssertTrue(app.staticTexts["Watch time"].waitForExistence(timeout: 5), "turning keeps the page")
        app.buttons["settings-playback"].tap()
        XCTAssertTrue(app.staticTexts["Long Videos"].waitForExistence(timeout: 5) || app.switches["autoplayShort"].waitForExistence(timeout: 5))
        shot("61-settings-sideways")

        XCUIDevice.shared.orientation = .portrait
        if !pad { XCTAssertTrue(app.tabBars.buttons["Playback"].waitForExistence(timeout: 5), "upright again has tabs") }
        XCTAssertTrue(app.switches["autoplayShort"].waitForExistence(timeout: 5), "and the same page")
        app.buttons["settingsDone"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: app.buttons["settingsDone"].firstMatch)], timeout: 5)
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 5), "back where it was")
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settingsDone"].firstMatch.waitForExistence(timeout: 5), "and it opens again")
    }

    /// Long-pressing a creator on Home offers its page, which opens outside the app. Needs a test Mac with @musiccat.
    func test13_OpenCreator() {
        app.launchArguments = ["-curatedHome", "-muteCurated"]
        app.launchEnvironment["CURATED_TEST_PAIR"] = "\(testMac):123456"
        app.launch()
        let creator = app.buttons["@musiccat"].firstMatch
        XCTAssertTrue(creator.waitForExistence(timeout: 30))
        creator.press(forDuration: 1.2)
        let open = app.buttons["Open in TikTok"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        shot("62-open-creator")
        open.tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").wait(for: .runningForeground, timeout: 15))
    }

    /// Adding a creator on the test Mac: the form comes from it, a mistake comes back on its field, then it's added.
    func test14_AddCreator() {
        app.launchArguments = ["-curatedSettings", "-muteCurated", "-curatedHome"]
        app.launch()
        app.buttons["addCreator"].firstMatch.tap()
        let input = app.textFields["field-input"].firstMatch
        let appeared = input.waitForExistence(timeout: 10)
        shot("69-add-creator-opening")
        XCTAssertTrue(appeared)
        shot("70-add-creator")
        input.tap()
        input.typeText("not a user!!")
        app.buttons["addCreatorSend"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["error-input"].firstMatch.waitForExistence(timeout: 10), "the Mac's complaint shows on the field")
        shot("71-add-creator-error")
        input.tap()
        input.press(forDuration: 1.2)
        for _ in 0..<14 { input.typeText(XCUIKeyboardKey.delete.rawValue) }
        input.typeText("https://www.youtube.com/@uitestchannel")
        XCTAssertTrue(app.switches["field-longForm"].firstMatch.waitForExistence(timeout: 5), "a YouTube link shows YouTube's fields")
        shot("72-add-creator-youtube")
        app.buttons["addCreatorSend"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Added"].waitForExistence(timeout: 10))
        shot("73-add-creator-added")
        app.alerts["Added"].buttons["OK"].tap()
    }

    /// Picking older videos on the test Mac, from a long creator's gallery. Needs @jawed with long videos on it.
    func test15_OlderVideos() {
        app.launchArguments = ["-curatedHome", "-muteCurated"]
        app.launchEnvironment["CURATED_TEST_OLDER"] = "1"
        app.launch()
        let tile = app.buttons["Me at the zoo"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30))
        sleep(2)  // The thumbnail, through the Mac.
        shot("74-older-videos")
        tile.tap()
        app.buttons["olderSend"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Sent to Your Mac"].waitForExistence(timeout: 10))
        shot("75-older-sent")
        app.alerts["Sent to Your Mac"].buttons["OK"].tap()
    }

    /// Home's +, then a picked older video: it comes to this device by itself, with Settings never opened.
    func test17_RequestedVideoArrives() {
        app.launchArguments = ["-curatedHome", "-muteCurated"]
        app.launchEnvironment["CURATED_TEST_PAIR"] = "\(testMac):123456"
        app.launchEnvironment["CURATED_TEST_OLDER"] = "1"
        app.launch()
        let tile = app.buttons["Me at the zoo"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30))
        tile.tap()
        app.buttons["olderSend"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Sent to Your Mac"].waitForExistence(timeout: 10))
        shot("78-older-comes-here")
        app.alerts["Sent to Your Mac"].buttons["OK"].tap()
        sleep(1)
        let plus = app.buttons["homeAddCreator"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        shot("79-home-plus")
        plus.tap()
        XCTAssertTrue(app.textFields["field-input"].firstMatch.waitForExistence(timeout: 15))
        shot("80-add-creator-from-home")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(75)  // The Mac downloads it, and the sync started by its finishing fetches it.
        app.buttons["Settings"].firstMatch.tap()
        let arrived = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'new video'")).firstMatch
        XCTAssertTrue(arrived.waitForExistence(timeout: 10), "the sync after the Mac's download says what came")
        shot("81-requested-arrived")
        app.buttons["syncForms"].firstMatch.tap()
        sleep(1)
        shot("82-sync-menu")
    }
}
