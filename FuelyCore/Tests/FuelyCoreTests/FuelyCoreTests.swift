import Testing
@testable import FuelyCore

struct FuelyCoreTests {
    @Test func appGroupIDIsSet() {
        #expect(FuelyCore.appGroupID == "group.com.afgaghifari.fuely")
    }
}
