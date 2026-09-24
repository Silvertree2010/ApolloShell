enum CSSMotionProperties {
    static let entries: [CSSPropertyEntry] = [
        CSSPropertyEntry("transition") { components, _ in .transitions(try CSSMotionParser.transitions(components)) },
        CSSPropertyEntry("-apollo-appear") { components, _ in .appear(try CSSMotionParser.appear(components)) },
        CSSPropertyEntry("-apollo-disappear") { components, _ in .appear(try CSSMotionParser.appear(components)) },
        CSSPropertyEntry("transform") { components, _ in .transform(try CSSMotionParser.transform(components)) },
        CSSPropertyEntry("animation-delay") { components, _ in .duration(try CSSRead.duration(CSSRead.single(components))) },
        CSSPropertyEntry("animation") { components, _ in try CSSMotionParser.animation(components) },
    ]
}
