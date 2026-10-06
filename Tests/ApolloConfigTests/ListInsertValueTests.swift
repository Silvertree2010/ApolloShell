import Testing
@testable import ApolloConfig

@Suite("list.insert value=")
struct ListInsertValueTests {
    @Test("value= ist im Schema erlaubt wie zur Laufzeit")
    func valueAccepted() {
        let result = SchemaStageTests.pipeline("""
        var items "[]"
        panel "p" {
            button {
                on-click {
                    list.insert "items" value="x"
                }
            }
        }
        """)
        #expect(SchemaStageTests.errors(result).isEmpty)
    }
}
