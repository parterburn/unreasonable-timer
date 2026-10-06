import XCTest
import TimerCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

private func makeEngine(seconds: Int, countOver: Bool = true, people: Int? = nil) -> TimerEngine {
    TimerEngine(config: TimerConfig(seconds: seconds, countOver: countOver, people: people))
}

final class FormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(TimerFormat.clock(0), "0:00")
        XCTAssertEqual(TimerFormat.clock(5), "0:05")
        XCTAssertEqual(TimerFormat.clock(59), "0:59")
        XCTAssertEqual(TimerFormat.clock(60), "1:00")
        XCTAssertEqual(TimerFormat.clock(600), "10:00")
        XCTAssertEqual(TimerFormat.clock(3599), "59:59")
        XCTAssertEqual(TimerFormat.clock(3600), "1:00:00")
        XCTAssertEqual(TimerFormat.clock(3661), "1:01:01")
        XCTAssertEqual(TimerFormat.clock(86_400), "24:00:00")
    }

    func testHumanize() {
        XCTAssertEqual(TimerFormat.humanize(45), "45 sec")
        XCTAssertEqual(TimerFormat.humanize(60), "1 min")
        XCTAssertEqual(TimerFormat.humanize(3599), "59 min")
        XCTAssertEqual(TimerFormat.humanize(3600), "1hr 0min")
        XCTAssertEqual(TimerFormat.humanize(7500), "2hr 5min")
    }

    func testDurationLabel() {
        XCTAssertEqual(TimerFormat.durationLabel(5), "5sec")
        XCTAssertEqual(TimerFormat.durationLabel(90), "1min 30sec")
        XCTAssertEqual(TimerFormat.durationLabel(3600), "1hr")
        XCTAssertEqual(TimerFormat.durationLabel(3661), "1hr 1min 1sec")
    }

    func testRubyToI() {
        XCTAssertEqual(TimerFormat.rubyToI("90"), 90)
        XCTAssertEqual(TimerFormat.rubyToI("90abc"), 90)
        XCTAssertEqual(TimerFormat.rubyToI(" 12"), 12)
        XCTAssertEqual(TimerFormat.rubyToI("-5"), -5)
        XCTAssertEqual(TimerFormat.rubyToI("+7"), 7)
        XCTAssertEqual(TimerFormat.rubyToI("abc"), 0)
        XCTAssertEqual(TimerFormat.rubyToI(""), 0)
        XCTAssertEqual(TimerFormat.rubyToI("1e3"), 1)
        XCTAssertEqual(TimerFormat.rubyToI("99999999999999999999999"), Int.max)
    }
}

final class CountdownTests: XCTestCase {
    func testStartsPausedAtFullTime() {
        let engine = makeEngine(seconds: 600)
        let snap = engine.snapshot(now: t0)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(snap.displayText, "10:00")
        XCTAssertTrue(snap.isPaused)
        XCTAssertFalse(snap.isWarning)
        XCTAssertEqual(snap.progress, 1)
        XCTAssertEqual(snap.heat, 0)
    }

    func testRemainingRoundsUpOnSecondBoundaries() {
        var engine = makeEngine(seconds: 10)
        engine.start(now: t0)
        engine.tick(now: at(0.4)); XCTAssertEqual(engine.remaining, 10)
        engine.tick(now: at(0.999)); XCTAssertEqual(engine.remaining, 10)
        engine.tick(now: at(1.0)); XCTAssertEqual(engine.remaining, 9)
        engine.tick(now: at(1.5)); XCTAssertEqual(engine.remaining, 9)
        engine.tick(now: at(9.0)); XCTAssertEqual(engine.remaining, 1)
        engine.tick(now: at(10.0)); XCTAssertEqual(engine.remaining, 0)
    }

    func testStartIgnoredWhenRunningOrExpired() {
        var engine = makeEngine(seconds: 5, countOver: false)
        engine.start(now: t0)
        let firstEnd = engine.endsAt
        engine.start(now: at(2))
        XCTAssertEqual(engine.endsAt, firstEnd)

        engine.tick(now: at(5))
        XCTAssertTrue(engine.isExpired)
        engine.start(now: at(6))
        XCTAssertFalse(engine.isRunning)
    }

    func testPauseAndResumeKeepRemaining() {
        var engine = makeEngine(seconds: 10)
        engine.start(now: t0)
        engine.tick(now: at(3.2))
        XCTAssertEqual(engine.remaining, 7)
        engine.pause()
        XCTAssertFalse(engine.isRunning)
        XCTAssertTrue(engine.snapshot(now: at(50)).isPaused)

        engine.start(now: at(100))
        XCTAssertEqual(engine.endsAt, at(107))
        engine.tick(now: at(100.5))
        XCTAssertEqual(engine.remaining, 7)
    }

    func testWarningAndFinalThresholds() {
        var engine = makeEngine(seconds: 60)
        engine.start(now: t0)

        engine.tick(now: at(44))   // 16 left
        var snap = engine.snapshot(now: at(44))
        XCTAssertFalse(snap.isWarning)
        XCTAssertFalse(snap.isFinal)

        engine.tick(now: at(45))   // 15 left
        snap = engine.snapshot(now: at(45))
        XCTAssertTrue(snap.isWarning)
        XCTAssertFalse(snap.isFinal)

        engine.tick(now: at(50))   // 10 left
        snap = engine.snapshot(now: at(50))
        XCTAssertTrue(snap.isWarning)
        XCTAssertTrue(snap.isFinal)
    }

    func testOvertimeCountsUpWhileRunning() {
        var engine = makeEngine(seconds: 5)
        engine.start(now: t0)
        engine.tick(now: at(5))
        var snap = engine.snapshot(now: at(5))
        XCTAssertTrue(snap.isExpired)
        XCTAssertTrue(snap.isOvertime)
        XCTAssertEqual(snap.displayText, "+0:00")
        XCTAssertTrue(engine.isRunning)

        engine.tick(now: at(12.4))
        snap = engine.snapshot(now: at(12.4))
        XCTAssertEqual(snap.displayText, "+0:07")
        XCTAssertEqual(snap.compactText, "+0:07")
        XCTAssertEqual(snap.overtimeSeconds, 7)
        XCTAssertFalse(snap.isWarning)
        XCTAssertFalse(snap.isPaused)
    }

    func testStopsAtZeroWhenNotCountingOver() {
        var engine = makeEngine(seconds: 5, countOver: false)
        engine.start(now: t0)
        let events = engine.tick(now: at(5.3))
        XCTAssertEqual(events, [.zeroReached])
        XCTAssertFalse(engine.isRunning)

        let snap = engine.snapshot(now: at(5.3))
        XCTAssertTrue(snap.isExpired)
        XCTAssertFalse(snap.isOvertime)
        XCTAssertFalse(snap.isPaused)
        XCTAssertEqual(snap.displayText, "Time is up!")
        XCTAssertEqual(snap.compactText, "0:00")
        XCTAssertEqual(snap.heat, 0.5)
    }

    func testToggleAfterExpiryResets() {
        var engine = makeEngine(seconds: 5, countOver: false)
        engine.start(now: t0)
        engine.tick(now: at(6))
        engine.toggle(now: at(7))
        XCTAssertEqual(engine.remaining, 5)
        XCTAssertFalse(engine.isRunning)

        engine.toggle(now: at(8))
        XCTAssertTrue(engine.isRunning)
        engine.toggle(now: at(9))
        XCTAssertFalse(engine.isRunning)
    }

    func testToggleDuringOvertimeResets() {
        var engine = makeEngine(seconds: 5)
        engine.start(now: t0)
        engine.tick(now: at(9))
        XCTAssertTrue(engine.isRunning)
        engine.toggle(now: at(9))
        XCTAssertEqual(engine.remaining, 5)
        XCTAssertEqual(engine.overtimeSeconds, 0)
        XCTAssertFalse(engine.isRunning)
    }

    func testResetRestoresEverything() {
        var engine = makeEngine(seconds: 30)
        engine.start(now: t0)
        engine.tick(now: at(40))
        engine.reset()
        let snap = engine.snapshot(now: at(40))
        XCTAssertEqual(snap.displayText, "0:30")
        XCTAssertEqual(snap.overtimeSeconds, 0)
        XCTAssertTrue(snap.isPaused)
    }

    func testLoadReplacesTimer() {
        var engine = makeEngine(seconds: 30)
        engine.start(now: t0)
        engine.load(TimerConfig(seconds: 90))
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.remaining, 90)
    }
}

final class AdjustTests: XCTestCase {
    func testAdjustWhilePaused() {
        var engine = makeEngine(seconds: 10)
        engine.adjust(by: 15, now: t0)
        XCTAssertEqual(engine.remaining, 25)
        XCTAssertFalse(engine.isRunning)
        engine.adjust(by: -15, now: t0)
        engine.adjust(by: -15, now: t0)
        XCTAssertEqual(engine.remaining, 0)
        XCTAssertFalse(engine.isRunning)
    }

    func testAdjustWhileRunningMovesTheDeadline() {
        var engine = makeEngine(seconds: 60)
        engine.start(now: t0)
        engine.tick(now: at(10))
        engine.adjust(by: 15, now: at(10))
        XCTAssertEqual(engine.remaining, 65)
        XCTAssertEqual(engine.endsAt, at(75))
    }

    func testAdjustToZeroWhileCountingOverKeepsRunning() {
        var engine = makeEngine(seconds: 20)
        engine.start(now: t0)
        engine.tick(now: at(10))
        let events = engine.adjust(by: -15, now: at(10))
        XCTAssertEqual(engine.remaining, 0)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(events, [.zeroReached])
    }

    func testAdjustToZeroWhenNotCountingOverStops() {
        var engine = makeEngine(seconds: 20, countOver: false)
        engine.start(now: t0)
        engine.tick(now: at(10))
        engine.adjust(by: -15, now: at(10))
        XCTAssertEqual(engine.remaining, 0)
        XCTAssertFalse(engine.isRunning)
    }

    func testAddingTimeDuringOvertimeResumesCountdown() {
        var engine = makeEngine(seconds: 5)
        engine.start(now: t0)
        engine.tick(now: at(9))
        XCTAssertEqual(engine.overtimeSeconds, 4)

        engine.adjust(by: 15, now: at(9))
        let snap = engine.snapshot(now: at(9))
        XCTAssertEqual(engine.remaining, 15)
        XCTAssertEqual(engine.overtimeSeconds, 0)
        XCTAssertFalse(snap.isExpired)
        XCTAssertTrue(snap.isRunning)
        XCTAssertTrue(snap.isWarning)
    }
}

final class SeekTests: XCTestCase {
    func testSeekJumpsToAFractionOfTheFullTime() {
        var engine = makeEngine(seconds: 600)
        engine.seek(toFraction: 0.25, now: t0)
        XCTAssertEqual(engine.remaining, 150)
        XCTAssertFalse(engine.isRunning)

        engine.start(now: t0)
        engine.tick(now: at(10))
        engine.seek(toFraction: 0.5, now: at(10))
        XCTAssertEqual(engine.remaining, 300)
        XCTAssertEqual(engine.endsAt, at(310))
        engine.tick(now: at(20))
        XCTAssertEqual(engine.remaining, 290)
    }

    func testSeekNeverEndsTheTimer() {
        var engine = makeEngine(seconds: 600)
        XCTAssertEqual(engine.seconds(atFraction: 0), 1)
        XCTAssertEqual(engine.seconds(atFraction: -2), 1)
        XCTAssertEqual(engine.seconds(atFraction: 1.4), 600)
        XCTAssertEqual(engine.seconds(atFraction: 0.501), 301)
        engine.seek(toFraction: 0, now: t0)
        XCTAssertEqual(engine.remaining, 1)
        XCTAssertFalse(engine.isExpired)
    }

    func testSeekIntoTheLastSecondsWhileRunning() {
        var engine = makeEngine(seconds: 600)
        engine.start(now: t0)
        let events = engine.seek(toFraction: 0.02, now: at(1))
        XCTAssertEqual(engine.remaining, 12)
        XCTAssertEqual(events, [.warningEntered])
    }
}

final class AppearanceTests: XCTestCase {
    func testProgressFraction() {
        var engine = makeEngine(seconds: 100)
        engine.start(now: t0)
        engine.tick(now: at(25))
        XCTAssertEqual(engine.snapshot(now: at(25)).progress, 0.75, accuracy: 1e-9)
        // Between ticks the bar keeps moving smoothly.
        XCTAssertEqual(engine.snapshot(now: at(25.5)).progress, 0.745, accuracy: 1e-9)
    }

    func testProgressNeverExceedsOne() {
        var engine = makeEngine(seconds: 100)
        engine.adjust(by: 15, now: t0)
        XCTAssertEqual(engine.snapshot(now: t0).progress, 1)
    }

    func testHeatRampsOverTheLastFifteenSeconds() {
        var engine = makeEngine(seconds: 60)
        engine.start(now: t0)

        engine.tick(now: at(44))
        XCTAssertEqual(engine.snapshot(now: at(44)).heat, 0)

        engine.tick(now: at(52.5))
        XCTAssertEqual(engine.snapshot(now: at(52.5)).heat, 0.15, accuracy: 1e-9)

        engine.tick(now: at(59.5))
        XCTAssertEqual(engine.snapshot(now: at(59.5)).heat, 0.3 * (14.5 / 15), accuracy: 1e-9)
    }

    func testOvertimeHeatBuildsThenHolds() {
        var engine = makeEngine(seconds: 10)
        engine.start(now: t0)

        engine.tick(now: at(10))
        XCTAssertEqual(engine.snapshot(now: at(10)).heat, 0.35, accuracy: 1e-9)

        engine.tick(now: at(70))
        XCTAssertEqual(engine.snapshot(now: at(70)).heat, 0.675, accuracy: 1e-9)

        engine.tick(now: at(130))
        XCTAssertEqual(engine.snapshot(now: at(130)).heat, 1.0, accuracy: 1e-9)

        engine.tick(now: at(1000))
        XCTAssertEqual(engine.snapshot(now: at(1000)).heat, 1.0, accuracy: 1e-9)
    }

    func testCompactText() {
        var engine = makeEngine(seconds: 300)
        engine.start(now: t0)
        engine.tick(now: at(27.5))
        XCTAssertEqual(engine.snapshot(now: at(27.5)).compactText, "4:33")
    }

    func testCostLine() {
        var one = makeEngine(seconds: 5, people: 1)
        one.start(now: t0)
        XCTAssertNil(one.snapshot(now: t0).costText)
        one.tick(now: at(10))
        XCTAssertEqual(one.snapshot(now: at(10)).costText, "1 person waiting · 5 sec of the room’s time")

        var room = makeEngine(seconds: 5, people: 30)
        room.start(now: t0)
        room.tick(now: at(95))
        XCTAssertEqual(room.snapshot(now: at(95)).costText, "30 people waiting · 45 min of the room’s time")

        var noPeople = makeEngine(seconds: 5)
        noPeople.start(now: t0)
        noPeople.tick(now: at(10))
        XCTAssertNil(noPeople.snapshot(now: at(10)).costText)

        var stopped = makeEngine(seconds: 5, countOver: false, people: 10)
        stopped.start(now: t0)
        stopped.tick(now: at(10))
        XCTAssertNil(stopped.snapshot(now: at(10)).costText)
    }
}

final class EventTests: XCTestCase {
    func testEventsFireOncePerTransition() {
        var engine = makeEngine(seconds: 20)
        XCTAssertEqual(engine.start(now: t0), [])

        XCTAssertEqual(engine.tick(now: at(4.5)), [])               // 16 left
        XCTAssertEqual(engine.tick(now: at(5.0)), [.warningEntered]) // 15 left
        XCTAssertEqual(engine.tick(now: at(5.2)), [])
        XCTAssertEqual(engine.tick(now: at(9.0)), [])               // 11 left
        XCTAssertEqual(engine.tick(now: at(10.0)), [.finalTick])    // 10 left
        XCTAssertEqual(engine.tick(now: at(10.4)), [])
        XCTAssertEqual(engine.tick(now: at(11.0)), [.finalTick])    // 9 left
        XCTAssertEqual(engine.tick(now: at(19.0)), [.finalTick])    // 1 left
        XCTAssertEqual(engine.tick(now: at(20.0)), [.zeroReached])
        XCTAssertEqual(engine.tick(now: at(21.0)), [])
        XCTAssertEqual(engine.tick(now: at(30.0)), [])
    }

    func testSkippedTimeReportsEveryTransitionOnce() {
        var engine = makeEngine(seconds: 30)
        engine.start(now: t0)
        engine.tick(now: at(1))
        // A long stall (App Nap, sleep) jumps straight into the final seconds.
        XCTAssertEqual(engine.tick(now: at(26)), [.warningEntered, .finalTick])
    }

    func testNoEventsWhilePaused() {
        var engine = makeEngine(seconds: 20)
        XCTAssertEqual(engine.adjust(by: -15, now: t0), [])   // 5 left, but not running
        XCTAssertEqual(engine.adjust(by: -15, now: t0), [])   // 0 left, still paused
        XCTAssertEqual(engine.reset(), [])
    }

    func testResetAllowsEventsToFireAgain() {
        var engine = makeEngine(seconds: 5, countOver: false)
        engine.start(now: t0)
        XCTAssertEqual(engine.tick(now: at(5)), [.zeroReached])
        engine.reset()
        engine.start(now: at(10))
        XCTAssertEqual(engine.tick(now: at(15)), [.zeroReached])
    }
}

final class ConfigTests: XCTestCase {
    func testDefaults() {
        let config = TimerConfig(seconds: 300)
        XCTAssertNil(config.leadText)
        XCTAssertEqual(config.warningText, "Please take your seats.")
        XCTAssertEqual(config.doneText, "Time is up!")
        XCTAssertTrue(config.countOver)
        XCTAssertNil(config.people)
        XCTAssertEqual(config.theme, .dark)
    }

    func testClamping() {
        XCTAssertEqual(TimerConfig(seconds: 0).seconds, 1)
        XCTAssertEqual(TimerConfig(seconds: -50).seconds, 1)
        XCTAssertEqual(TimerConfig(seconds: 999_999).seconds, 86_400)
        XCTAssertNil(TimerConfig(seconds: 60, people: 0).people)
        XCTAssertNil(TimerConfig(seconds: 60, people: -3).people)
        XCTAssertEqual(TimerConfig(seconds: 60, people: 20_000).people, 10_000)
        XCTAssertEqual(TimerConfig(seconds: 60, people: 12).people, 12)
    }

    func testTextIsSquishedAndTruncated() {
        let config = TimerConfig(seconds: 60, leadText: "  a   b \n c ", warningText: "  take   a seat ")
        XCTAssertEqual(config.leadText, "a b c")
        XCTAssertEqual(config.warningText, "take a seat")

        let long = String(repeating: "x", count: 200)
        let limited = TimerConfig(seconds: 60, leadText: long, warningText: long, doneText: long)
        XCTAssertEqual(limited.leadText?.count, 120)
        XCTAssertEqual(limited.warningText.count, 120)
        XCTAssertEqual(limited.doneText.count, 60)
    }

    func testBlankTextRules() {
        let config = TimerConfig(seconds: 60, leadText: "   ", warningText: "", doneText: "  ")
        XCTAssertNil(config.leadText)                      // blank lead is no lead
        XCTAssertEqual(config.warningText, "")             // blank warning stays blank, not the default
        XCTAssertEqual(config.doneText, "Time is up!")     // blank done falls back
    }

    func testCodableRoundTrip() throws {
        let config = TimerConfig(seconds: 90, leadText: "Hi", warningText: "Wrap up", doneText: "Done", countOver: false, people: 4, theme: .light)
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(TimerConfig.self, from: data), config)
    }

    func testDecodingToleratesMissingFields() throws {
        let config = try JSONDecoder().decode(TimerConfig.self, from: Data(#"{"seconds": 300}"#.utf8))
        XCTAssertEqual(config, TimerConfig(seconds: 300))
    }

    func testDecodingReappliesLimits() throws {
        let config = try JSONDecoder().decode(TimerConfig.self, from: Data(#"{"seconds": 9999999, "people": 99999}"#.utf8))
        XCTAssertEqual(config.seconds, 86_400)
        XCTAssertEqual(config.people, 10_000)
    }

    func testSummaryMatchesTheWebHistoryRow() {
        XCTAssertEqual(
            TimerConfig(seconds: 300).summary,
            "“Please take your seats.” · “Time is up!” at 00:00 · Keeps counting"
        )
        XCTAssertEqual(
            TimerConfig(seconds: 300, leadText: "Intro", warningText: "Wrap up", doneText: "Stop", countOver: false, people: 1, theme: .light).summary,
            "“Intro” then “Wrap up” · “Stop” at 00:00 · Stops at 00:00 · 1 person · Light mode"
        )
        XCTAssertEqual(
            TimerConfig(seconds: 300, warningText: "", people: 8).summary,
            "No text under timer · “Time is up!” at 00:00 · Keeps counting · 8 people"
        )
    }

    func testDurationLabel() {
        XCTAssertEqual(TimerConfig(seconds: 3930).durationLabel, "1hr 5min 30sec")
    }
}

final class LinkParsingTests: XCTestCase {
    private func items(_ query: String) -> [URLQueryItem] {
        query.split(separator: "&").map { pair in
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return URLQueryItem(name: String(halves[0]), value: halves.count > 1 ? String(halves[1]) : "")
        }
    }

    func testFullQuery() throws {
        let config = try XCTUnwrap(TimerConfig(queryItems: items("time=300&text=Wrap&lead=Intro&done=Bye&over=0&people=12&theme=light")))
        XCTAssertEqual(config, TimerConfig(seconds: 300, leadText: "Intro", warningText: "Wrap", doneText: "Bye", countOver: false, people: 12, theme: .light))
    }

    func testTimeIsRequiredAndPositive() {
        XCTAssertNil(TimerConfig(queryItems: []))
        XCTAssertNil(TimerConfig(queryItems: items("time=0")))
        XCTAssertNil(TimerConfig(queryItems: items("time=-30")))
        XCTAssertNil(TimerConfig(queryItems: items("time=abc")))
        XCTAssertEqual(TimerConfig(queryItems: items("time=90abc"))?.seconds, 90)
        XCTAssertEqual(TimerConfig(queryItems: items("time=999999"))?.seconds, 86_400)
    }

    func testDefaultsForAbsentParams() throws {
        let config = try XCTUnwrap(TimerConfig(queryItems: items("time=60")))
        XCTAssertEqual(config.warningText, "Please take your seats.")
        XCTAssertTrue(config.countOver)
        XCTAssertEqual(config.theme, .dark)
        XCTAssertNil(config.people)
    }

    func testEmptyTextParamMeansNoWarningText() throws {
        XCTAssertEqual(try XCTUnwrap(TimerConfig(queryItems: items("time=60&text="))).warningText, "")
    }

    func testOnlyLightThemeIsRecognised() {
        XCTAssertEqual(TimerConfig(queryItems: items("time=60&theme=light"))?.theme, .light)
        XCTAssertEqual(TimerConfig(queryItems: items("time=60&theme=blue"))?.theme, .dark)
    }

    func testEcoLink() throws {
        let link = "https://eco.example.com/timer?time=300&text=Hello+there&lead=Be%20brief&edit=1"
        let config = try XCTUnwrap(TimerConfig(link: link))
        XCTAssertEqual(config.seconds, 300)
        XCTAssertEqual(config.warningText, "Hello there")
        XCTAssertEqual(config.leadText, "Be brief")
    }

    func testCustomSchemeLink() {
        XCTAssertEqual(TimerConfig(link: "untimer://start?time=60")?.seconds, 60)
        XCTAssertEqual(TimerConfig(link: "  untimer://open?time=45\n")?.seconds, 45)
    }

    func testTrailingSlashAndCurlyQuotes() throws {
        XCTAssertEqual(TimerConfig(link: "https://x.test/timer/?time=60")?.seconds, 60)
        let config = try XCTUnwrap(TimerConfig(link: "https://x.test/timer?time=60&done=%E2%80%9CBye%E2%80%9D"))
        XCTAssertEqual(config.doneText, "“Bye”")
    }

    func testRejectsOtherLinks() {
        XCTAssertNil(TimerConfig(link: "https://x.test/other?time=60"))
        XCTAssertNil(TimerConfig(link: "https://x.test/timer"))
        XCTAssertNil(TimerConfig(link: "ftp://x.test/timer?time=60"))
        XCTAssertNil(TimerConfig(link: "just some text"))
        XCTAssertNil(TimerConfig(link: ""))
    }
}

final class HistoryTests: XCTestCase {
    func testMostRecentFirstWithoutRepeats() {
        let a = TimerConfig(seconds: 60)
        let b = TimerConfig(seconds: 120)
        var list = TimerHistory.remembering(a, in: [])
        list = TimerHistory.remembering(b, in: list)
        XCTAssertEqual(list, [b, a])
        list = TimerHistory.remembering(a, in: list)
        XCTAssertEqual(list, [a, b])
    }

    func testDifferentOptionsAreDifferentTimers() {
        let plain = TimerConfig(seconds: 60)
        let light = TimerConfig(seconds: 60, theme: .light)
        XCTAssertEqual(TimerHistory.remembering(light, in: [plain]), [light, plain])
    }

    func testCappedAtFive() {
        var list: [TimerConfig] = []
        for n in 1...8 { list = TimerHistory.remembering(TimerConfig(seconds: n * 60), in: list) }
        XCTAssertEqual(list.count, 5)
        XCTAssertEqual(list.map(\.seconds), [480, 420, 360, 300, 240])
    }
}
