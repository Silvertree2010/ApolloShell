enum WMSettings {
    static let all: [NodeSchema] = [
        NodeSchema(
            name: "layout",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["dwindle", "canvas"]), allowsExpression: false, doc: "Vorgabe-Layout.")],
            contexts: [.wmBlock],
            doc: "wählt das Standard-Layout des Fenstermanagers.",
            example: "layout \"dwindle\""
        ),
        NodeSchema(
            name: "gaps",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "inner", type: .number, defaultValue: .number(10), allowsExpression: false, doc: "Abstand zwischen Fenstern in pt.", feature: "wm"),
                PropertySchema(name: "outer", type: .number, defaultValue: .number(12), allowsExpression: false, doc: "Abstand zum Bildschirmrand in pt.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Abstände zwischen und um gekachelte Fenster.",
            example: "gaps inner=10 outer=12"
        ),
        NodeSchema(
            name: "focus-follows-mouse",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "enabled", type: .bool, allowsExpression: false, doc: "ob Fokus dem Zeiger folgt.")],
            properties: [
                PropertySchema(name: "delay", type: .duration, defaultValue: .string("25ms"), allowsExpression: false, doc: "Verzögerung, bevor der Fokus folgt.", feature: "wm"),
                PropertySchema(name: "suspend-with", type: .string, defaultValue: .null, allowsExpression: false, doc: "Modifikatoren, die die Funktion vorübergehend abschalten.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "ob und wie der Fokus dem Mauszeiger folgt.",
            example: "focus-follows-mouse #true delay=\"25ms\""
        ),
        NodeSchema(
            name: "drag",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "super", type: .string, defaultValue: .string("hyper"), allowsExpression: false, doc: "Modifikatoren für Ziehen und Grösse ändern.", feature: "wm"),
                PropertySchema(name: "scroll-pans", type: .bool, defaultValue: .bool(true), allowsExpression: false, doc: "Scrollen schiebt den Canvas-Streifen.", feature: "wm"),
                PropertySchema(name: "scroll-speed", type: .number, defaultValue: .number(1.5), allowsExpression: false, doc: "Geschwindigkeit des Canvas-Schiebens.", feature: "wm"),
                PropertySchema(name: "invert-scroll", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "kehrt die Scrollrichtung um.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Mausbedienung des Fenstermanagers.",
            example: "drag super=\"hyper\" scroll-pans=#true"
        ),
        NodeSchema(
            name: "resize-animation",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["smooth", "snap", "proxy"]), allowsExpression: false, doc: "Art der Grössenänderungs-Animation.")],
            contexts: [.wmBlock],
            doc: "wie Fenster ihre Grösse ändern.",
            example: "resize-animation \"smooth\""
        ),
        NodeSchema(
            name: "spring",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "response", type: .number, defaultValue: .number(0.28), allowsExpression: false, doc: "Federantwortzeit in s.", feature: "wm"),
                PropertySchema(name: "frame-rate", type: .number, defaultValue: .number(120), allowsExpression: false, doc: "Bildrate der Animation.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Federparameter der Kachel-Animationen.",
            example: "spring response=0.28"
        ),
        NodeSchema(
            name: "tab-bar",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "height", type: .number, defaultValue: .number(30), allowsExpression: false, doc: "Höhe der Tab-Leiste in pt.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Grösse der Tab-Leiste gruppierter Fenster.",
            example: "tab-bar height=30"
        ),
        NodeSchema(
            name: "canvas",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "column-width", type: .number, defaultValue: .number(0.5), allowsExpression: false, doc: "Anteil 0…1 der Spaltenbreite.", feature: "wm"),
                PropertySchema(name: "center-focused", type: .bool, defaultValue: .bool(false), allowsExpression: false, doc: "zentriert das fokussierte Fenster.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Einstellungen des Canvas-Layouts.",
            example: "canvas column-width=0.5"
        ),
        NodeSchema(
            name: "scratchpad",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "share", type: .number, defaultValue: .number(0.7), allowsExpression: false, doc: "Anteil 0…1 des Bildschirms.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Grösse des Scratchpads.",
            example: "scratchpad share=0.7"
        ),
        NodeSchema(
            name: "terminal",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "bundleIDs", type: .string, variadic: true, allowsExpression: false, doc: "Bundle-IDs, die erste installierte gewinnt.")],
            contexts: [.wmBlock],
            doc: "wählt das Terminal für wm.terminal.",
            example: "terminal \"com.mitchellh.ghostty\" \"com.apple.Terminal\""
        ),
        NodeSchema(
            name: "apple-desktops",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "enabled", type: .bool, allowsExpression: false, doc: "ob wm.desktop Apples Spaces schaltet.")],
            contexts: [.wmBlock],
            doc: "ob der Fenstermanager Apples Spaces oder eigene Arbeitsbereiche nutzt.",
            example: "apple-desktops #true"
        ),
        NodeSchema(
            name: "rule",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "kind", type: .enumeration(["float", "tile", "ignore"]), allowsExpression: false, doc: "wie passende Fenster behandelt werden.")],
            properties: [
                PropertySchema(name: "app", type: .string, defaultValue: .null, allowsExpression: false, doc: "Bundle-ID oder App-Name ohne Gross-/Kleinschreibung.", feature: "wm"),
                PropertySchema(name: "title", type: .string, defaultValue: .null, allowsExpression: false, doc: "Teiltext des Fenstertitels.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "Regel für einzelne Fenster nach App oder Titel.",
            example: "rule \"float\" app=\"com.apple.calculator\""
        ),
        NodeSchema(
            name: "reserve-panels",
            category: .wmSetting,
            feature: "wm",
            arguments: [ArgumentSchema(name: "enabled", type: .bool, allowsExpression: false, doc: "ob Streifen von panel reserve=#true freigehalten werden.")],
            contexts: [.wmBlock],
            doc: "ob Panels mit reserve den Kachelbereich verkleinern.",
            example: "reserve-panels #true"
        ),
        NodeSchema(
            name: "reserve",
            category: .wmSetting,
            feature: "wm",
            properties: [
                PropertySchema(name: "top", type: .number, defaultValue: .null, allowsExpression: false, doc: "reservierter Streifen oben in pt.", feature: "wm"),
                PropertySchema(name: "left", type: .number, defaultValue: .null, allowsExpression: false, doc: "reservierter Streifen links in pt.", feature: "wm"),
                PropertySchema(name: "bottom", type: .number, defaultValue: .null, allowsExpression: false, doc: "reservierter Streifen unten in pt.", feature: "wm"),
                PropertySchema(name: "right", type: .number, defaultValue: .null, allowsExpression: false, doc: "reservierter Streifen rechts in pt.", feature: "wm"),
                PropertySchema(name: "screen", type: .string, defaultValue: .null, allowsExpression: false, doc: "auf welchem Bildschirm die Reservierung gilt.", feature: "wm"),
            ],
            contexts: [.wmBlock],
            doc: "zusätzlicher reservierter Streifen für fremde Leisten, mehrfach erlaubt.",
            example: "reserve top=24"
        ),
    ]
}
