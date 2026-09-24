struct KDLSyntaxError: Error, Equatable {
    var message: String
    var start: Int
    var end: Int
}
