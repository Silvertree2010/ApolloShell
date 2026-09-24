import Foundation
import ApolloBase
import ApolloKDL
import ApolloConfig

enum IRTestBuilder {
    static let file = "/config/shell.kdl"

    static func span(line: Int, column: Int = 1) -> SourceSpan {
        SourceSpan(file: file, start: SourcePosition(offset: 0, line: line, column: column), end: SourcePosition(offset: 0, line: line, column: column + 1))
    }

    static func value(_ text: String, locals: Set<String> = [], line: Int = 1) -> CompiledValue {
        let at = span(line: line)
        switch ExpressionParser.parseTemplate(text, span: at) {
        case .success(let template):
            return CompiledValue(template: template, dependencies: template.dependencies(locals: locals), span: at)
        case .failure(let diagnostic):
            preconditionFailure(diagnostic.message)
        }
    }

    static func literal(_ constant: Value, line: Int = 1) -> CompiledValue {
        CompiledValue(template: .whole(.literal(constant)), dependencies: [], span: span(line: line))
    }

    static func action(_ name: String, _ arguments: [CompiledValue] = [], properties: [String: CompiledValue] = [:], line: Int = 1) -> ActionIR {
        .call(ActionCallIR(name: name, arguments: arguments, properties: properties, span: span(line: line)))
    }

    static func text(_ key: String, _ content: CompiledValue, properties: [String: CompiledValue] = [:], line: Int = 1) -> ChildIR {
        .element(ElementIR(kind: "text", key: key, arguments: [content], properties: properties, span: span(line: line)))
    }

    static func box(_ kind: String, key: String, properties: [String: CompiledValue] = [:], handlers: [HandlerIR] = [], children: [ChildIR], line: Int = 1) -> ChildIR {
        .element(ElementIR(kind: kind, key: key, properties: properties, handlers: handlers, children: children, span: span(line: line)))
    }

    static func sampleConfig() -> ConfigIR {
        let clockHandler = HandlerIR(
            name: "on-click",
            actions: [
                .repeatBlock(count: literal(.number(2), line: 12), body: [action("toggle-var", [literal(.string("clock-seconds"), line: 13)], line: 13)]),
                .when(condition: value("{var.clock-seconds}", line: 14), then: [action("toggle", [literal(.string("calendar"), line: 14)], line: 14)], otherwise: []),
            ],
            span: span(line: 11)
        )
        let appList = EachIR(
            key: "1",
            variable: "app",
            indexVariable: "i",
            list: value("{apps.running}", line: 20),
            itemKey: value("{app.bundle-id}", locals: ["app", "i"], line: 20),
            body: [
                .element(ElementIR(
                    kind: "button",
                    key: "0",
                    properties: ["id": value("app-{app.bundle-id}", locals: ["app", "i"], line: 21)],
                    handlers: [HandlerIR(name: "on-click", actions: [action("open-app", [value("{app.bundle-id}", locals: ["app", "i"], line: 22)], line: 22)], span: span(line: 22))],
                    menu: MenuIR(items: [
                        .item(title: literal(.string("Quit"), line: 23), properties: [:], actions: [action("apps.quit", [value("{app.bundle-id}", locals: ["app", "i"], line: 23)], line: 23)]),
                        .separator,
                        .source(kind: "app-windows", properties: ["app": value("{app.bundle-id}", locals: ["app", "i"], line: 24)]),
                    ]),
                    children: [text("0", value("{i + 1}. {app.name}", locals: ["app", "i"], line: 25), line: 25)],
                    span: span(line: 21)
                )),
            ]
        )
        let battery = WhenIR(
            key: "2",
            condition: value("{battery.present}", line: 30),
            then: [text("0", value("{battery.percent | percent}", line: 31), line: 31)],
            otherwise: [text("0", literal(.string("No battery"), line: 33), line: 33)]
        )
        let tabs = SwitchIR(
            key: "3",
            subject: value("{var.dashboard-tab}", line: 40),
            cases: [
                SwitchCaseIR(values: [literal(.string("media"), line: 41)], body: [text("0", literal(.string("Media"), line: 41), line: 41)]),
                SwitchCaseIR(values: [literal(.string("performance"), line: 42), literal(.string("weather"), line: 42)], body: [
                    .dynamicUse(DynamicUseIR(key: "0", name: value("dashboard-{var.dashboard-tab}", line: 42))),
                ]),
            ],
            otherwise: [text("0", literal(.string("Overview"), line: 43), line: 43)]
        )
        let bar = SurfaceIR(
            kind: "panel",
            id: "bar",
            properties: ["edge": literal(.string("top"), line: 9), "visible": value("{!shell.fullscreen}", line: 9)],
            handlers: [HandlerIR(name: "on-open", actions: [action("set", [literal(.string("dashboard-tab"), line: 10), literal(.string("media"), line: 10)], line: 10)], span: span(line: 10))],
            keyHandlers: [KeyHandlerIR(chord: "escape", actions: [action("close", [literal(.string("bar"), line: 10)], line: 10)])],
            children: [
                box("row", key: "clock", properties: ["id": literal(.string("clock"), line: 11)], handlers: [clockHandler], children: [
                    text("0", value("{clock.now | date 'HH:mm'}", line: 15), line: 15),
                ], line: 11),
                .each(appList),
                .when(battery),
                .switchOn(tabs),
            ],
            span: span(line: 9)
        )
        let weather = DefineIR(
            name: "dashboard-weather",
            parameters: [ParameterIR(name: "compact", type: .bool, defaultValue: .scalar(literal(.bool(false), line: 50)))],
            body: [text("0", value("{weather.temperature}", line: 51), line: 51)],
            span: span(line: 50)
        )
        return ConfigIR(
            id: "sample",
            root: URL(fileURLWithPath: "/config"),
            files: [URL(fileURLWithPath: file)],
            styleSheets: [StyleRef(url: URL(fileURLWithPath: "/config/shell.css"), span: span(line: 2))],
            requiredVersion: "0.2.0",
            requiredFeatures: ["core"],
            vars: [
                VarDecl(name: "dashboard-tab", type: .string, defaultValue: .scalar(literal(.string("media"), line: 3)), persist: true, derived: nil, span: span(line: 3)),
                VarDecl(name: "clock-seconds", type: .bool, defaultValue: .scalar(literal(.bool(false), line: 4)), persist: false, derived: nil, span: span(line: 4)),
            ],
            surfaces: [bar],
            binds: [BindIR(id: "alt+space", chord: literal(.string("alt+space"), line: 60), actions: [action("toggle", [literal(.string("launcher"), line: 60)], line: 60)], span: span(line: 60))],
            events: [EventHandlerIR(event: "config.loaded", actions: [action("notify", [literal(.string("Loaded"), line: 61)], line: 61)], span: span(line: 61))],
            defines: [weather.name: weather],
            blocks: ["poll": [BlockIR(name: "poll", nodes: [KDLNode(name: "poll", arguments: [KDLValue(.string("uptime"))])], compiled: ["interval": literal(.string("5s"), line: 70)])]]
        )
    }
}
