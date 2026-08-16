import Foundation
import Testing
@testable import Food4ThoughtCore

@Suite("USDA mapping")
struct USDAFoodMapperTests {

    private func decode(_ json: String) throws -> USDASearchResponse {
        try JSONDecoder().decode(USDASearchResponse.self, from: Data(json.utf8))
    }

    @Test("a Foundation food maps its per-100g nutrients onto a 100g serving")
    func foundationFood() throws {
        let response = try decode("""
        {"foods":[{
          "fdcId": 171077,
          "description": "Chicken, broiler, breast, grilled",
          "dataType": "Foundation",
          "foodNutrients": [
            {"nutrientNumber":"208","unitName":"KCAL","value":165.0},
            {"nutrientNumber":"203","unitName":"G","value":31.02},
            {"nutrientNumber":"205","unitName":"G","value":0.0},
            {"nutrientNumber":"204","unitName":"G","value":3.57}
          ]}]}
        """)

        let items = USDAFoodMapper.items(from: response)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == .external("171077"))
        #expect(item.source == .usdaFDC)
        #expect(item.name == "Chicken, broiler, breast, grilled")
        #expect(item.serving == Serving(amount: 100, unit: "g"))
        #expect(abs(item.facts.calories - 165) < 0.001)
        #expect(abs(item.facts.protein - 31.02) < 0.001)
    }

    @Test("a branded food's label serving becomes the serving, with nutrients scaled to it")
    func brandedFoodScalesToLabelServing() throws {
        // The API quotes foodNutrients per 100 g even for branded rows, so a
        // 240 g serving has to be scaled up — quoting per-100g values against a
        // 240 g serving would under-report every entry by more than half.
        let response = try decode("""
        {"foods":[{
          "fdcId": 999001,
          "description": "GREEK YOGURT, PLAIN",
          "dataType": "Branded",
          "brandOwner": "Chobani",
          "servingSize": 240.0,
          "servingSizeUnit": "g",
          "foodNutrients": [
            {"nutrientNumber":"208","unitName":"KCAL","value":59.0},
            {"nutrientNumber":"203","unitName":"G","value":10.0},
            {"nutrientNumber":"205","unitName":"G","value":3.6},
            {"nutrientNumber":"204","unitName":"G","value":0.4}
          ]}]}
        """)

        let item = try #require(USDAFoodMapper.items(from: response).first)

        #expect(item.brand == "Chobani")
        #expect(item.serving == Serving(amount: 240, unit: "g"))
        #expect(abs(item.facts.calories - 141.6) < 0.001)
        #expect(abs(item.facts.protein - 24) < 0.001)
    }

    @Test("a serving quoted in millilitres falls back to 100 g rather than guessing a density")
    func nonMassServingFallsBack() throws {
        let response = try decode("""
        {"foods":[{
          "fdcId": 999002,
          "description": "ORANGE JUICE",
          "dataType": "Branded",
          "servingSize": 250.0,
          "servingSizeUnit": "ml",
          "foodNutrients": [{"nutrientNumber":"208","unitName":"KCAL","value":45.0}]
        }]}
        """)

        let item = try #require(USDAFoodMapper.items(from: response).first)

        #expect(item.serving == Serving(amount: 100, unit: "g"))
        #expect(abs(item.facts.calories - 45) < 0.001)
    }

    @Test("energy in kilojoules converts rather than being read as kcal")
    func kilojoulesConvert() throws {
        let response = try decode("""
        {"foods":[{
          "fdcId": 999003,
          "description": "Test food",
          "dataType": "Foundation",
          "foodNutrients": [{"nutrientNumber":"268","unitName":"kJ","value":418.4}]
        }]}
        """)

        let item = try #require(USDAFoodMapper.items(from: response).first)

        // 418.4 kJ / 4.184 = 100 kcal. Reading it raw would be a 4x overcount.
        #expect(abs(item.facts.calories - 100) < 0.01)
    }

    @Test("a food with no energy figure is dropped, not shown as zero calories")
    func energylessFoodIsDropped() throws {
        // A 0 kcal row in a search result is worse than a missing one: it logs
        // silently and quietly under-counts the day.
        let response = try decode("""
        {"foods":[{
          "fdcId": 999004,
          "description": "Mystery food",
          "dataType": "Foundation",
          "foodNutrients": [{"nutrientNumber":"203","unitName":"G","value":5.0}]
        }]}
        """)

        #expect(USDAFoodMapper.items(from: response).isEmpty)
    }

    @Test("a blank description is dropped — food_items requires a name")
    func namelessFoodIsDropped() throws {
        let response = try decode("""
        {"foods":[{
          "fdcId": 999005,
          "description": "   ",
          "dataType": "Foundation",
          "foodNutrients": [{"nutrientNumber":"208","unitName":"KCAL","value":100.0}]
        }]}
        """)

        #expect(USDAFoodMapper.items(from: response).isEmpty)
    }
}
