import XCTest

@MainActor final class WanderlogUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  private func launch(reset: Bool = true) -> XCUIApplication {
    let app = XCUIApplication(); app.launchArguments = reset ? ["--ui-test", "--ui-test-reset"] : ["--ui-test"]
    app.launch(); return app
  }
  private func myJourneys(_ app: XCUIApplication) {
    let tab = app.tabBars.buttons["旅程"]; XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
    app.buttons["筛选旅程"].tap()
    let toggle = app.switches["包含示例旅程"]; XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    let control = toggle.switches.firstMatch
    if control.exists { control.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
    app.buttons["完成"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["1 段旅程 · 1 张照片"].waitForExistence(timeout: 5))
  }
  private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  func testMigrationNavigationPhotoViewerAndDraftRetention() throws {
    let app = launch()
    XCTAssertTrue(app.buttons["地图居中"].waitForExistence(timeout: 10)); attach(app, name: "native-map")
    for country in ["法国", "日本", "土耳其", "泰国", "中国"] {
      let pin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", country + "，")).firstMatch
      XCTAssertTrue(pin.isHittable, "World fit should keep \(country) visible")
    }
    myJourneys(app); attach(app, name: "native-journeys")
    app.buttons["journey-card-local-ui-fixture"].tap()
    XCTAssertTrue(app.staticTexts["旧记录迁移验收"].waitForExistence(timeout: 5))
    app.buttons["detail-hero-photo"].tap()
    XCTAssertTrue(app.buttons["关闭照片"].waitForExistence(timeout: 5)); attach(app, name: "native-photo-viewer")
    let photoPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
    let lowerPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
    photoPoint.doubleTap()
    photoPoint.press(forDuration: 0.05, thenDragTo: lowerPoint)
    XCTAssertTrue(app.buttons["关闭照片"].exists, "Dragging an enlarged photo must pan rather than dismiss")
    photoPoint.doubleTap()
    photoPoint.press(forDuration: 0.05, thenDragTo: lowerPoint)
    XCTAssertTrue(app.buttons["关闭旅程详情"].waitForExistence(timeout: 5))
    app.buttons["关闭旅程详情"].tap()
    XCTAssertTrue(app.tabBars.buttons["旅程"].isSelected)
    app.buttons["添加旅程"].tap()
    let title = app.textFields["这段旅程的名字"]; XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap(); title.typeText("Draft retained")
    app.buttons["取消"].firstMatch.tap(); app.buttons["添加旅程"].tap()
    XCTAssertEqual(app.textFields["这段旅程的名字"].value as? String, "Draft retained")
    attach(app, name: "native-draft-retained")
  }
  func testManualPlaceNameAndMapSelection() throws {
    let app = launch()
    XCTAssertTrue(app.buttons["添加旅程"].waitForExistence(timeout: 10)); app.buttons["添加旅程"].tap()
    app.buttons["自定义"].tap()
    let name = app.textFields["地点名称"]; XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap(); name.typeText("Manual place")
    XCTAssertEqual(name.value as? String, "Manual place")
    name.typeText("\n")
    let map = app.otherElements["manual-place-map"].firstMatch
    if map.exists { map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() } else { app.maps.firstMatch.tap() }
    let done = app.buttons["manual-place-confirm"]
    let enabled = NSPredicate(format: "enabled == true")
    expectation(for: enabled, evaluatedWith: done); waitForExpectations(timeout: 5)
    done.tap()
    XCTAssertTrue(app.staticTexts["Manual place"].waitForExistence(timeout: 5)); attach(app, name: "native-add-journey")
  }
  func testWorldCountryCityPreviewAndReturn() throws {
    let app = launch()
    let country = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "中国，")).firstMatch
    XCTAssertTrue(country.waitForExistence(timeout: 10)); country.tap()
    let province = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "浙江省，")).firstMatch
    XCTAssertTrue(province.waitForExistence(timeout: 5)); province.tap()
    let city = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "温州，")).firstMatch
    XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
    XCTAssertTrue(app.staticTexts["旧记录迁移验收"].waitForExistence(timeout: 5)); attach(app, name: "native-map-preview")
    app.buttons.containing(.staticText, identifier: "旧记录迁移验收").firstMatch.tap()
    XCTAssertTrue(app.buttons["detail-hero-photo"].waitForExistence(timeout: 5))
    app.buttons["关闭旅程详情"].tap()
    app.buttons["世界"].tap()
    XCTAssertTrue(country.waitForExistence(timeout: 5)); XCTAssertTrue(country.isHittable)
  }
  func testDeletePersistsAndDoesNotReimportLegacyOnRelaunch() throws {
    let app = launch(); myJourneys(app)
    app.buttons["journey-card-local-ui-fixture"].tap()
    let delete = app.buttons["删除旅程"]
    for _ in 0..<5 { if delete.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(delete.isHittable); delete.tap()
    app.buttons["删除旅程及应用内照片"].tap()
    XCTAssertTrue(app.staticTexts["0 段旅程 · 0 张照片"].waitForExistence(timeout: 5))
    app.terminate(); app.launchArguments = ["--ui-test"]; app.launch()
    app.tabBars.buttons["旅程"].tap()
    XCTAssertTrue(app.staticTexts["5 段旅程 · 11 张照片"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["journey-card-local-ui-fixture"].exists)
  }
  func testCombinedFiltersAndClearKeepSamplePreference() throws {
    let app = launch(); myJourneys(app)
    app.buttons["筛选旅程"].tap()
    app.buttons["2026 年"].tap()
    XCTAssertTrue(app.buttons["完成"].exists)
    app.buttons["城市"].tap()
    let city = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "filter-city-")).firstMatch
    XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
    XCTAssertTrue(app.buttons["完成"].exists)
    app.buttons["完成"].tap()
    XCTAssertTrue(app.buttons["journey-card-local-ui-fixture"].exists)
    app.buttons["清除筛选"].tap()
    XCTAssertTrue(app.staticTexts["1 段旅程 · 1 张照片"].exists)
    XCTAssertFalse(app.buttons["清除筛选"].exists)
  }
  func testEditLegacyJourneyThenDeleteAndUndo() throws {
    let app = launch(); myJourneys(app)
    app.buttons["journey-card-local-ui-fixture"].tap()
    let edit = app.buttons["编辑旅程"]
    for _ in 0..<5 { if edit.isHittable { break }; app.swipeUp() }
    edit.tap()
    let title = app.textFields["这段旅程的名字"]
    XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" Updated")
    app.buttons["保存"].tap()
    XCTAssertTrue(app.buttons["关闭旅程详情"].waitForExistence(timeout: 5))
    app.buttons["关闭旅程详情"].tap()
    XCTAssertTrue(app.tabBars.buttons["旅程"].isSelected)
    XCTAssertTrue(app.staticTexts["旧记录迁移验收 Updated"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["2026.09"].exists)
    app.buttons["journey-card-local-ui-fixture"].tap()
    let delete = app.buttons["删除旅程"]
    for _ in 0..<5 { if delete.isHittable { break }; app.swipeUp() }
    delete.tap(); app.buttons["删除旅程及应用内照片"].tap()
    let undo = app.buttons["撤销"]; XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
    XCTAssertTrue(app.buttons["journey-card-local-ui-fixture"].waitForExistence(timeout: 5))
    app.terminate(); app.launchArguments = ["--ui-test"]; app.launch(); app.tabBars.buttons["旅程"].tap()
    XCTAssertTrue(app.staticTexts["旧记录迁移验收 Updated"].waitForExistence(timeout: 5))
  }
  func testFormErrorRemainsVisibleAtTop() throws {
    let app = launch(); app.buttons["添加旅程"].tap(); app.buttons["保存"].tap()
    XCTAssertTrue(app.staticTexts["请选择地点。"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["请选择地点。"].isHittable)
  }

  func testMixedPhotoRatiosAndMasonry() throws {
    let app = XCUIApplication(); app.launchArguments = ["--ui-test", "--ui-test-reset", "--ui-test-photo-layout"]; app.launch()
    app.tabBars.buttons["旅程"].tap()
    app.buttons["journey-card-local-ui-fixture"].tap()
    let hero = app.buttons["detail-hero-photo"]
    XCTAssertTrue(hero.waitForExistence(timeout: 5))
    let portrait = NSPredicate { _, _ in hero.frame.height / hero.frame.width > 1.45 }
    expectation(for: portrait, evaluatedWith: hero); waitForExpectations(timeout: 5)
    attach(app, name: "uncropped-portrait-hero")
    app.swipeUp()
    let first = app.buttons["detail-photo-0"], second = app.buttons["detail-photo-1"]
    XCTAssertTrue(first.waitForExistence(timeout: 5)); XCTAssertTrue(second.waitForExistence(timeout: 5))
    let loaded = NSPredicate { _, _ in first.frame.height / first.frame.width > 1.4 && second.frame.height / second.frame.width < 0.75 }
    expectation(for: loaded, evaluatedWith: first); waitForExpectations(timeout: 5)
    XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 3)
    let third = app.buttons["detail-photo-2"]
    XCTAssertLessThan(third.frame.minY, first.frame.maxY, "Third photo should fill the shorter column")
    attach(app, name: "mixed-photo-masonry")
  }
  func testEmptyMapGuidesToAddJourney() throws {
    let app = XCUIApplication(); app.launchArguments = ["--ui-test", "--ui-test-reset", "--ui-test-empty"]; app.launch()
    let add = app.buttons["添加第一段旅程"]
    XCTAssertTrue(add.waitForExistence(timeout: 10)); XCTAssertTrue(add.isHittable)
    attach(app, name: "map-empty-guidance"); add.tap()
    XCTAssertTrue(app.textFields["这段旅程的名字"].waitForExistence(timeout: 5))
  }
  func testBodyAndCaptionScaleWithDynamicType() throws {
    let normal = launch(); myJourneys(normal)
    normal.buttons["journey-card-local-ui-fixture"].tap()
    let note = normal.staticTexts["detail-note"]
    let caption = normal.staticTexts["detail-location"]
    XCTAssertTrue(note.waitForExistence(timeout: 5)); let noteHeight = note.frame.height
    let captionHeight = caption.frame.height
    normal.terminate()
    let large = XCUIApplication()
    large.launchArguments = ["--ui-test", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    large.launch(); XCTAssertTrue(large.buttons["地图居中"].waitForExistence(timeout: 10))
    attach(large, name: "map-accessibility-largest-text")
    large.tabBars.buttons["旅程"].tap()
    large.buttons["journey-card-local-ui-fixture"].tap()
    let enlarged = large.staticTexts["detail-note"]
    XCTAssertTrue(enlarged.waitForExistence(timeout: 5))
    XCTAssertGreaterThan(enlarged.frame.height, noteHeight * 1.5)
    XCTAssertGreaterThan(large.staticTexts["detail-location"].frame.height, captionHeight * 1.5)
    attach(large, name: "detail-accessibility-largest-text")
  }

}
