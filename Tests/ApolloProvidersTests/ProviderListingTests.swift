import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("apollo providers")
struct ProviderListingTests {
    @Test("Listet jedes Feld jedes Registry-Providers mit Wert aus der Fixture")
    func listsEveryField() {
        let harness = ProviderHarness()
        let fixture = ProviderFixture.parse(SpecFixture.text, file: "fixture.kdl")
        let providers = FixtureProvider.all(fixture: fixture)
        for provider in providers {
            harness.register(provider)
            _ = harness.keepAwake(provider.schema.id)
        }
        let schemas = providers.map(\.schema)
        let lines = ProviderListing.lines(schemas: schemas) { harness.store.value($0) }
        let expected = schemas.reduce(0) { $0 + $1.fields.count }
        #expect(lines.count == expected)
        #expect(expected > 150)
        #expect(lines.contains("battery.percent = 0.76"))
        #expect(lines.contains("battery.charging = false"))
        #expect(lines.contains("media.title = \"Starboy\""))
        #expect(lines.contains("clock.now = \"2026-09-24T07:41:00Z\""))
        #expect(lines.contains("weather.place = {\"name\":\"Chur\",\"latitude\":46.85,\"longitude\":9.53}"))
        #expect(lines.contains("keyboard.caps-lock = null"))
        #expect(lines.contains { $0.hasPrefix("apps.dock = [{\"bundle-id\":\"com.apple.finder\"") })
        for schema in schemas {
            for field in schema.fields {
                let key = ([schema.id] + field.path).joined(separator: ".") + " = "
                #expect(lines.contains { $0.hasPrefix(key) }, "\(key)")
            }
        }
    }

    @Test("JSON-Darstellung aller Werttypen, sortiert nach Provider")
    func jsonForAllTypes() {
        #expect(ProviderListing.json(.null) == "null")
        #expect(ProviderListing.json(.number(3)) == "3")
        #expect(ProviderListing.json(.number(-0.5)) == "-0.5")
        #expect(ProviderListing.json(.number(.nan)) == "null")
        #expect(ProviderListing.json(.string("a\"b\n")) == "\"a\\\"b\\n\"")
        #expect(ProviderListing.json(.list([.bool(true), .null])) == "[true,null]")
        #expect(ProviderListing.json(.image(ImageRef(source: "app-icon", id: "com.apple.Safari"))) == "{\"image\":\"app-icon:com.apple.Safari\"}")
        let schemas = [ProviderSchema(id: "zeta", fields: [FieldSchema(path: ["a"], type: .number, update: .push, doc: "")], doc: ""), ProviderSchema(id: "alpha", fields: [FieldSchema(path: ["b", "c"], type: .number, update: .push, doc: "")], doc: "")]
        #expect(ProviderListing.lines(schemas: schemas) { _ in .null } == ["alpha.b.c = null", "zeta.a = null"])
    }
}
