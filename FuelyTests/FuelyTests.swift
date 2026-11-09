import Testing
import FuelyCore

struct FuelyTests {
    @Test func fuelyCoreIsLinked() {
        #expect(!FuelyCore.appGroupID.isEmpty)
    }
}
