import Foundation
import SwiftData
import XCTest
@testable import AutoWave

@MainActor
final class ProfileEntityTests: XCTestCase {
    func testCurrentCreatesOneProfileAndReturnsSameRowOnRepeatCalls() throws {
        let schema = Schema([ProfileEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let first = ProfileEntity.current(in: context)
        let second = ProfileEntity.current(in: context)
        let profiles = try context.fetch(FetchDescriptor<ProfileEntity>())

        XCTAssertTrue(first === second)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(first.nickname, "플레이어")
        XCTAssertEqual(first.avatarSymbol, "water.waves")
        XCTAssertEqual(first.avatarTint, "#4FC3F7")
    }

    func testNicknameValidationTrimsValidInputAndRejectsInvalidInput() {
        XCTAssertEqual(ProfileEntity.validatedNickname("  파도  "), "파도")
        XCTAssertNil(ProfileEntity.validatedNickname("   "))
        XCTAssertNil(ProfileEntity.validatedNickname(String(repeating: "가", count: 13)))
        XCTAssertEqual(ProfileEntity.validatedNickname(String(repeating: "가", count: 12))?.count, 12)
    }

    func testNoteSpeedMultiplierDefaultsAndPersistsAcrossContexts() throws {
        let schema = Schema([ProfileEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let profile = ProfileEntity()

        context.insert(profile)
        XCTAssertEqual(profile.noteSpeedMultiplier, 1.0)

        profile.noteSpeedMultiplier = 1.5
        try context.save()

        let reloadedContext = ModelContext(container)
        let reloaded = try reloadedContext.fetch(FetchDescriptor<ProfileEntity>())

        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.noteSpeedMultiplier, 1.5)
    }
}
