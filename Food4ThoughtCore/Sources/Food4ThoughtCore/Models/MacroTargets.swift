public struct MacroTargets: Equatable, Sendable {
    public let proteinGrams: Double
    public let carbsGrams: Double
    public let fatGrams: Double

    public init(proteinGrams: Double, carbsGrams: Double, fatGrams: Double) {
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
    }
}
