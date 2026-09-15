import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Emblem im Sitzungsmenue")
struct SessionEmblemTests {
    @Test("Reaktion auf Knopf unter Maus oder Auswahl", arguments: [
        (SessionAction?.none, EmblemReaction.idle),
        (SessionAction.sleep, EmblemReaction.sleep),
        (SessionAction.shutDown, EmblemReaction.farewell),
        (SessionAction.restart, EmblemReaction.farewell),
        (SessionAction.logOut, EmblemReaction.think),
    ])
    func reacting(action: SessionAction?, expected: EmblemReaction) {
        #expect(EmblemReaction.reacting(to: action) == expected)
    }

    @Test("Nach einer Einmal-Bewegung bleibt die Ruhe-Reaktion", arguments: [
        (SessionAction?.none, EmblemReaction.idle),
        (SessionAction.sleep, EmblemReaction.sleep),
        (SessionAction.shutDown, EmblemReaction.idle),
        (SessionAction.restart, EmblemReaction.idle),
        (SessionAction.logOut, EmblemReaction.think),
    ])
    func resting(action: SessionAction?, expected: EmblemReaction) {
        #expect(EmblemReaction.resting(for: action) == expected)
        #expect(!expected.isOneShot)
    }

    @Test("Nur Oeffnen und Abschied sind einmalig", arguments: [
        (EmblemReaction.greet, true),
        (EmblemReaction.farewell, true),
        (EmblemReaction.idle, false),
        (EmblemReaction.sleep, false),
        (EmblemReaction.think, false),
    ])
    func oneShots(reaction: EmblemReaction, oneShot: Bool) {
        #expect(reaction.isOneShot == oneShot)
    }

    @Test("Einmal-Bewegung meldet erst am Ende fertig", arguments: [EmblemReaction.greet, .farewell])
    func finishesAtDuration(reaction: EmblemReaction) throws {
        let duration = try #require(reaction.duration)
        #expect(!EmblemPose.at(reaction, time: duration * 0.99, startAngle: 0).finished)
        #expect(EmblemPose.at(reaction, time: duration, startAngle: 0).finished)
    }

    @Test("Einmal-Bewegung endet in der Ruhepose mit Ruhegeschwindigkeit", arguments: [EmblemReaction.greet, .farewell])
    func oneShotEndsAtRest(reaction: EmblemReaction) throws {
        let end = EmblemPose.at(reaction, time: try #require(reaction.duration), startAngle: 0)
        #expect(abs(end.moonSpeed - EmblemPose.idleSpeed) < 0.05)
        #expect(abs(end.planetScale - 1) < 0.001)
        #expect(abs(end.glow - EmblemPose.restGlow) < 0.001)
    }

    @Test("Schleifen beginnen in der Ruhepose", arguments: [EmblemReaction.idle, .sleep, .farewell, .think])
    func startsAtRest(reaction: EmblemReaction) {
        let start = EmblemPose.at(reaction, time: 0, startAngle: 0)
        #expect(abs(start.planetScale - 1) < 0.001)
        #expect(abs(start.glow - EmblemPose.restGlow) < 0.001)
        #expect(start.orbitTilt == 0)
        #expect(start.night == 0)
        #expect(abs(start.moonSpeed - EmblemPose.idleSpeed) < 0.05)
    }

    @Test("Im Ruhezustand bleibt der Mond stehen, die Nacht ist ganz da", arguments: [3.0, 10.0])
    func sleepSettles(time: Double) {
        let pose = EmblemPose.at(.sleep, time: time, startAngle: 0)
        #expect(abs(pose.moonSpeed) < 0.001)
        #expect(pose.night == 1)
        #expect(pose.stars.allSatisfy { $0 > 0 })
    }

    @Test("Beim Wechsel springt der Mond nicht", arguments: [
        (EmblemReaction.greet, EmblemReaction.think, 0.6),
        (EmblemReaction.idle, EmblemReaction.sleep, 4.0),
        (EmblemReaction.sleep, EmblemReaction.farewell, 7.5),
        (EmblemReaction.think, EmblemReaction.idle, 2.2),
    ])
    func switchKeepsMoon(from: EmblemReaction, to: EmblemReaction, after: Double) {
        let start = 1000.0
        var timeline = EmblemTimeline(from, at: start)
        let before = timeline.pose(at: start + after).moonAngle
        timeline.show(to, at: start + after)
        let after = timeline.pose(at: start + after).moonAngle
        #expect(timeline.reaction == to)
        #expect(abs(sin(before) - sin(after)) < 1e-9)
        #expect(abs(cos(before) - cos(after)) < 1e-9)
    }

    @Test("Dieselbe Reaktion nochmal startet nicht neu", arguments: [EmblemReaction.idle, .think])
    func sameReactionContinues(reaction: EmblemReaction) {
        var timeline = EmblemTimeline(reaction, at: 0)
        timeline.show(reaction, at: 5)
        #expect(timeline.startTime == 0)
    }

    @Test("Bewegung reduziert: feste Pose, der Mond immer am selben Ort", arguments: EmblemReaction.allCases)
    func stillPoses(reaction: EmblemReaction) {
        let pose = EmblemPose.still(reaction)
        #expect(pose.moonAngle == EmblemTimeline.restAngle)
        #expect(pose.moonSpeed == 0)
        #expect(pose.orbitTilt == 0)
    }

    @Test("Stehende Posen behalten die Aussage", arguments: [
        (EmblemReaction.sleep, 1.0, false),
        (EmblemReaction.think, 0.0, true),
        (EmblemReaction.idle, 0.0, false),
    ])
    func stillPosesKeepMeaning(reaction: EmblemReaction, night: Double, dots: Bool) {
        let pose = EmblemPose.still(reaction)
        #expect(pose.night == night)
        #expect(pose.dots.contains { $0 > 0 } == dots)
    }

    @Test("Bezierkurve des Menues: Endpunkte und Ueberschwinger", arguments: [0.0, 1.0])
    func menuCurveEnds(x: Double) {
        #expect(abs(EmblemPose.menuCurve(x) - x) < 1e-6)
    }

    @Test("Bezierkurve schiesst leicht ueber", arguments: [0.6])
    func menuCurveOvershoots(x: Double) {
        #expect(EmblemPose.menuCurve(x) > 1)
    }
}
