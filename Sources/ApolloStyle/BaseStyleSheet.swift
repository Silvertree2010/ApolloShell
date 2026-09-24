public enum BaseStyleSheet {
    public static let file = "base.css"

    public static let source = """
    :root {
      font-family: system-ui;
      font-size: 13px;
      color: -apple-system-label;
    }

    """

    public static let sheet: StyleSheet = StyleSheet.parse(source, file: file, origin: .base).0
}
