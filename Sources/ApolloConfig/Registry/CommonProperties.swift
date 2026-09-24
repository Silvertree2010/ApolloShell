enum CommonProperties {
    static let idArgument = ArgumentSchema(
        name: "id",
        type: .identifier,
        doc: "Kennung, je Oberfläche eindeutig; Ziel für flyout, popup und each."
    )

    static let baseline: [PropertySchema] = [
        PropertySchema(name: "id", type: .identifier, defaultValue: .null, doc: "Kennung, je Oberfläche eindeutig, Vorlage erlaubt."),
        PropertySchema(name: "class", type: .string, defaultValue: .null, doc: "CSS-Klassen, durch Leerzeichen getrennt."),
        PropertySchema(name: "style", type: .string, defaultValue: .null, doc: "CSS-Deklarationen nur für diesen Knoten."),
        PropertySchema(name: "visible", type: .bool, defaultValue: .bool(true), doc: "versteckt den Knoten, ohne Zustand zu verlieren."),
        PropertySchema(name: "tooltip", type: .string, defaultValue: .null, doc: "Hilfetext beim Verweilen."),
        PropertySchema(name: "label", type: .string, defaultValue: .null, doc: "Text für VoiceOver, Vorgabe aus tooltip oder Inhalt."),
        PropertySchema(name: "checked", type: .bool, defaultValue: .bool(false), doc: "setzt die Pseudoklasse :checked."),
        PropertySchema(name: "disabled", type: .bool, defaultValue: .bool(false), doc: "keine Eingaben, Pseudoklasse :disabled."),
        PropertySchema(name: "match-id", type: .string, defaultValue: .null, doc: "Elemente mit gleicher match-id gleiten beim Erscheinen ineinander."),
        PropertySchema(name: "menu-on", type: .string, defaultValue: .string("right-click"), doc: "was das Kontextmenü öffnet, mehrere durch Leerzeichen getrennt."),
    ]

    static let dragValue = PropertySchema(
        name: "drag-value",
        type: .value,
        defaultValue: .null,
        allowsExpression: true,
        doc: "macht das Element zur Ziehquelle, reserviert für 0.2.1.",
        stability: .experimental,
        feature: "drag-values"
    )

    static let fuseGroup = PropertySchema(
        name: "fuse-group",
        type: .string,
        defaultValue: .null,
        doc: "verschmilzt Oberflächen zu einer Fläche, reserviert für 0.2.1.",
        stability: .experimental,
        feature: "fusion"
    )

    static let elementProperties: [PropertySchema] = baseline + [dragValue]

    static let surfaceCommon: [PropertySchema] = [
        PropertySchema(name: "override", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "ersetzt eine gleichnamige Oberfläche aus einer eingebundenen Datei."),
        PropertySchema(name: "screen", type: .string, defaultValue: .null, allowsExpression: true, doc: "auf welchem Bildschirm es Instanzen gibt."),
        PropertySchema(name: "anchor", type: .enumeration(["top", "bottom", "left", "right", "top-left", "top-right", "bottom-left", "bottom-right", "center", "fill"]), defaultValue: .string("center"), doc: "woran die Oberfläche klebt."),
        PropertySchema(name: "area", type: .enumeration(["full", "below-menubar", "visible"]), defaultValue: .string("below-menubar"), doc: "Bezugsrechteck der Verankerung."),
        PropertySchema(name: "layer", type: .string, defaultValue: .null, doc: "Fensterebene, Vorgabe je Oberflächen-Art."),
        PropertySchema(name: "keyboard", type: .bool, defaultValue: .bool(false), doc: "ob die Oberfläche Tastatureingaben annimmt."),
        PropertySchema(name: "click-through", type: .oneOf([.bool, .enumeration(["auto"])]), defaultValue: .bool(false), doc: "ob Mausereignisse durchgehen; bool oder \"auto\" (nur dort nicht, wo ein Element mit Handler oder sichtbarem Hintergrund liegt)."),
        PropertySchema(name: "offset-x", type: .number, defaultValue: .number(0), doc: "Verschiebung entlang x gegenüber der verankerten Lage."),
        PropertySchema(name: "offset-y", type: .number, defaultValue: .number(0), doc: "Verschiebung entlang y gegenüber der verankerten Lage."),
        PropertySchema(name: "sticky", type: .bool, defaultValue: .bool(true), doc: "auf allen Spaces und im eigenen Space."),
        PropertySchema(name: "fullscreen", type: .enumeration(["hide", "show"]), defaultValue: .null, doc: "Verhalten auf einem Bildschirm mit Vollbild-App."),
        PropertySchema(name: "overhang", type: .bool, defaultValue: .bool(false), doc: "ragt um den Eckenradius über die verankerten Kanten."),
        PropertySchema(name: "safe-area", type: .bool, defaultValue: .bool(true), doc: "Inhalt beginnt unter Menüleiste und Notch."),
        PropertySchema(name: "shape", type: .enumeration(["rect", "fused"]), defaultValue: .string("rect"), doc: "ob offene flyout eine gemeinsame Form mit dem Hintergrund bilden."),
        fuseGroup,
    ]

    static let surfaceProperties: [PropertySchema] = baseline + surfaceCommon

    static let surfaceHandlers: [String] = ["on-open", "on-close", "on-closed", "key"]

    static let elementHandlers: [String] = [
        "on-click", "on-right-click", "on-middle-click", "on-double-click", "on-long-press",
        "on-scroll", "on-hover", "on-hover-end", "on-drop", "on-appear", "on-disappear",
    ]

    static let elementHandlerNode = NodeSchema(
        name: "menu",
        category: .element,
        arguments: [],
        properties: [
            PropertySchema(name: "side", type: .enumeration(["pointer", "right", "left", "below"]), defaultValue: .string("pointer"), doc: "wo das Menü aufgeht."),
            PropertySchema(name: "offset", type: .number, defaultValue: .number(6), doc: "Abstand in pt beim Aufgehen neben dem Element."),
        ],
        childContext: .menu,
        contexts: [.elementBody],
        doc: "gibt einem Element ein natives Kontextmenü.",
        example: "menu { item \"Copy\" { clipboard.copy \"{system.full-name}\" } }"
    )

    static let accessibilityAction = NodeSchema(
        name: "accessibility-action",
        category: .element,
        arguments: [ArgumentSchema(name: "title", type: .string, doc: "Titel der VoiceOver-Aktion.")],
        childContext: .actions,
        contexts: [.elementBody],
        doc: "gibt einem Element eine benannte VoiceOver-Aktion.",
        example: "accessibility-action \"Move Up\" { list.move \"items\" from=1 to=0 }"
    )
}
