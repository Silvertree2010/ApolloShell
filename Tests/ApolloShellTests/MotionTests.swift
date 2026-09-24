import Testing
import Foundation
import AppKit
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Render: Bewegung und Neuberechnung (styling.md 3.5, testing.md 4)", .serialized)
struct MotionTests {
    func style(_ css: String) throws -> ComputedStyle {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"x\" }", css: ".x { \(css) }")
        let element = try #require(session.surfaces.first?.root.first)
        return session.context.styles.resolve(StyleResolver.subject(for: element), ancestors: [], parent: nil)
    }

    @Test("animation: spin, pulse, wiggle, bounce mit Anzahl und negativer Verzögerung")
    func animationPoses() throws {
        let spin = try #require(AnimationSpec(try style("animation: spin 1s infinite;")))
        #expect(spin.kind == .spin && spin.count == nil)
        #expect(abs(spin.pose(spin.progress(elapsed: 0.25)).rotation - 90) < 0.001)
        let pulse = try #require(AnimationSpec(try style("animation: pulse 2s 2;")))
        #expect(abs(pulse.pose(pulse.progress(elapsed: 1)).opacity - 0.4) < 0.001)
        #expect(pulse.progress(elapsed: 4.1) == nil)
        #expect(pulse.pose(nil) == AnimationSpec.Pose())
        let bounce = try #require(AnimationSpec(try style("animation: bounce 440ms 1;")))
        #expect(abs(bounce.pose(bounce.progress(elapsed: 0.22)).offsetY + 10) < 0.001)
        let wiggle = try #require(AnimationSpec(try style("animation: wiggle 400ms infinite; animation-delay: -0.1s;")))
        #expect(abs(wiggle.pose(wiggle.progress(elapsed: 0)).rotation - 0.6) < 0.001)
        #expect(AnimationSpec(try style("animation: spin 1s infinite;"), reduceMotion: true) == nil)
        #expect(AnimationSpec(try style("animation: pulse 1s infinite;"), reduceMotion: true) != nil)
        #expect(AnimationSpec(try style("animation: none;")) == nil)
    }

    @Test("transition: Stiländerung animiert ausser value/content/match/size, Erscheinen nach -apollo-appear")
    func plan() throws {
        #expect(MotionPlan(try style("transition: opacity 200ms, value 1s;")).change != nil)
        #expect(MotionPlan(try style("transition: value 1s;")).change == nil)
        #expect(MotionPlan(try style("")).change == nil)
    }

    @Test("Hover auf einem von 40 Elementen berechnet nur dieses neu und bleibt unter einem Frame")
    func hoverRecalc() throws {
        let mounted = try Mounted.mount("""
        panel "t" anchor="left" {
            column {
                each i in="{[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39]}" {
                    button class="b" { stack class="dot" }
                }
            }
        }
        """, css: """
        #t { width: 60px; height: 900px; }
        .b { width: 40px; height: 20px; background: #eeeeee; transition: background 200ms; }
        .b:hover { background: #ff0000; }
        .dot { width: 4px; height: 4px; background: #000000; }
        .b:hover .dot { background: #ffffff; }
        """)
        let styles = mounted.session.context.styles
        let column = try #require(mounted.session.surfaces.first?.root.first)
        #expect(column.children.count == 40)
        let target = try #require(column.children.dropFirst(5).first)
        let warmup = try #require(column.children.dropFirst(20).first)
        for _ in 0..<3 {
            RunLoopPump.run(0.02)
            mounted.view.layoutSubtreeIfNeeded()
        }
        let coldComputed = styles.computed
        warmup.pseudo.insert(.hover)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.displayIfNeeded()
        RunLoopPump.run(0.05)
        let firstComputed = styles.computed - coldComputed
        warmup.pseudo.remove(.hover)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.displayIfNeeded()
        RunLoopPump.run(0.05)
        let lookups = styles.lookups
        let started = ContinuousClock.now
        target.pseudo.insert(.hover)
        mounted.view.layoutSubtreeIfNeeded()
        mounted.view.displayIfNeeded()
        let first = ContinuousClock.now - started
        RunLoopPump.run(0.05)
        let newLookups = styles.lookups - lookups
        var samples = [first]
        for round in 0..<8 {
            let begin = ContinuousClock.now
            if round.isMultiple(of: 2) { target.pseudo.remove(.hover) } else { target.pseudo.insert(.hover) }
            mounted.view.layoutSubtreeIfNeeded()
            mounted.view.displayIfNeeded()
            samples.append(ContinuousClock.now - begin)
            RunLoopPump.run(0.02)
        }
        let longest = try #require(samples.max())
        print("hover recalculation: \(newLookups) lookups, \(firstComputed) computed when cold, first \(first), max \(longest)")
        #expect(firstComputed > 0 && firstComputed <= 6)
        #expect(newLookups <= 20)
        #expect(longest <= Self.mainActorBlockBudget)
    }

    static let mainActorBlockBudget = Duration.microseconds(16_700)

    @Test("RunningAnimation schreibt ohne Animation keinen Zustand, mit Animation Neustart und Ende")
    func runningAnimationWritesOnlyWithSpec() async throws {
        var restarts = 0
        var finishes = 0
        await RunningAnimation.run(nil, restart: { restarts += 1 }, finish: { finishes += 1 })
        #expect(restarts == 0 && finishes == 0)
        let spec = try #require(AnimationSpec(try style("animation: pulse 10ms 1;")))
        await RunningAnimation.run(spec, restart: { restarts += 1 }, finish: { finishes += 1 })
        #expect(restarts == 1 && finishes == 1)
    }
}
