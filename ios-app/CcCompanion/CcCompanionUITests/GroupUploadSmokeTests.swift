//
//  GroupUploadSmokeTests.swift
//  CcCompanionUITests
//
//  Build 218 — XCUITest covering group-chat upload (PHPicker → /group/upload) end-to-end.
//
//  Setup: this source file is checked in but CcCompanion.xcodeproj currently has only a
//  single PBXNativeTarget (the app). To activate, add a "UI Testing Bundle" target via
//  Xcode → File → New → Target, attach this file, then `xcodebuild test` will pick it up.
//

#if canImport(XCTest)
import XCTest

final class GroupUploadSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testGroupUploadImage() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["UITEST_GROUP_UPLOAD_SMOKE": "1"]
        app.launch()

        // 切到 群聊 tab (FloatingTabBar 上 "群聊" 项)
        let groupTab = app.tabBars.buttons["群聊"]
        XCTAssertTrue(groupTab.waitForExistence(timeout: 5))
        groupTab.tap()

        // 点 + 按钮 (upload trigger)
        let plusBtn = app.buttons["plus.circle.fill"]
        XCTAssertTrue(plusBtn.waitForExistence(timeout: 5))
        plusBtn.tap()

        // 选 "图片"
        let imgBtn = app.buttons["图片"]
        if imgBtn.waitForExistence(timeout: 3) {
            imgBtn.tap()
        }

        // PHPicker 弹出 → 选第一张照片 → tap 选择
        let firstPhoto = app.scrollViews.images.firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 8))
        firstPhoto.tap()

        // 等待上传完成 (toast 或 bubble 出现)
        let uploadedHint = app.staticTexts["上传完成"]
        XCTAssertTrue(uploadedHint.waitForExistence(timeout: 15))

        // 截图存档
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "group-upload-smoke"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
