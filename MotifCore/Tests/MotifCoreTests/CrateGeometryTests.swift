import Testing
@testable import MotifCore

@Suite("Play's crate")
struct CrateGeometryTests {
    /// The iPhone's crate: a 232-point cover, 8 points between places.
    let pitch = 240.0

    // MARK: - The fan

    @Test("Records either side sit further out and smaller, one after another")
    func fanStepsOut() {
        #expect(CrateFan.reach(0) == 0)
        #expect(CrateFan.scale(0) == 1)
        for a in 1...6 {
            let (nearer, farther) = (Double(a - 1), Double(a))
            #expect(CrateFan.reach(farther) > CrateFan.reach(nearer))
            #expect(CrateFan.scale(farther) < CrateFan.scale(nearer))
        }
    }

    @Test("The first record beside the front is tucked just behind it, not clear of it")
    func firstRecordTucksBehind() {
        // Its inner edge, reach less half its width, falls inside the front cover's half.
        let innerEdge = CrateFan.reach(1) - CrateFan.scale(1) / 2
        #expect(innerEdge < 0.5)
        #expect(innerEdge > 0.3)
    }

    @Test("Records far out never shrink to nothing")
    func scaleHasAFloor() {
        #expect(CrateFan.scale(40) == 0.5)
    }

    @Test("A phone fits one record a side; a wide Mac window fits several", arguments: [
        (width: 402.0, side: 232.0, depth: 1.0),
        (width: 1528.0, side: 306.0, depth: 4.0),
    ])
    func depthFitsTheWidth(width: Double, side: Double, depth: Double) {
        #expect(CrateFan.depth(width: width, side: side) == depth)
    }

    @Test("Every record counted in the depth fits inside the fade at the edges")
    func depthFits() {
        for width in stride(from: 300.0, through: 3000, by: 50) {
            let side = 260.0
            let depth = CrateFan.depth(width: width, side: side)
            #expect(depth >= 1)
            #expect(depth <= Double(CrateFan.deepest))
            guard depth > 1 else { continue }
            let outerEdge = (CrateFan.reach(depth) + CrateFan.scale(depth) / 2) * side
            #expect(outerEdge <= width / 2 * 0.91)
        }
    }

    @Test("Before the width is known, one record a side")
    func depthWithoutWidth() {
        #expect(CrateFan.depth(width: 0, side: 232) == 1)
        #expect(CrateFan.depth(width: 400, side: 0) == 1)
    }

    // MARK: - Position

    @Test("The place in the middle is the nearest record's")
    func placeRounds() {
        #expect(CratePosition(offset: 0, pitch: pitch, places: 10).place == 0)
        #expect(CratePosition(offset: pitch * 0.49, pitch: pitch, places: 10).place == 0)
        #expect(CratePosition(offset: pitch * 0.51, pitch: pitch, places: 10).place == 1)
        #expect(CratePosition(offset: pitch * 7, pitch: pitch, places: 10).place == 7)
    }

    @Test("Pulled past an end, the place holds at the end rather than running off the row")
    func placeHoldsAtTheEnds() {
        #expect(CratePosition(offset: -pitch * 2, pitch: pitch, places: 10).place == 0)
        #expect(CratePosition(offset: pitch * 14, pitch: pitch, places: 10).place == 9)
    }

    @Test("Past an end only once pulled a hair beyond it, not while settling onto it")
    func pastEnd() {
        let places = 5
        let last = Double(places - 1) * pitch
        #expect(!CratePosition(offset: 0, pitch: pitch, places: places).isPastEnd)
        #expect(!CratePosition(offset: -pitch * 0.05, pitch: pitch, places: places).isPastEnd)
        #expect(CratePosition(offset: -pitch * 0.2, pitch: pitch, places: places).isPastEnd)
        #expect(!CratePosition(offset: last, pitch: pitch, places: places).isPastEnd)
        #expect(!CratePosition(offset: last + pitch * 0.05, pitch: pitch, places: places).isPastEnd)
        #expect(CratePosition(offset: last + pitch * 0.2, pitch: pitch, places: places).isPastEnd)
        #expect(!CratePosition(offset: pitch * 2, pitch: pitch, places: places).isPastEnd)
    }

    @Test("Scrolling one record changes the place once: one detent a record")
    func oneDetentARecord() {
        var changes = 0
        var previous = CratePosition(offset: 0, pitch: pitch, places: 10)
        for step in 0...240 {
            let position = CratePosition(offset: Double(step), pitch: pitch, places: 10)
            if position.place != previous.place { changes += 1 }
            previous = position
        }
        #expect(changes == 1)
        #expect(previous.place == 1)
    }

    @Test("An empty crate, or one not laid out yet, is at its start")
    func emptyPosition() {
        let empty = CratePosition(offset: 500, pitch: pitch, places: 0)
        #expect(empty.place == 0)
        #expect(!empty.isPastEnd)
        let unlaid = CratePosition(offset: 500, pitch: 0, places: 8)
        #expect(unlaid.place == 0)
        #expect(!unlaid.isPastEnd)
    }

    // MARK: - Coming to rest

    @Test("A scroll comes to rest with the nearest record in the middle")
    func restsOnARecord() {
        let last = pitch * 9
        #expect(CrateRest.offset(for: pitch * 2.3, from: nil, pitch: pitch, last: last) == pitch * 2)
        #expect(CrateRest.offset(for: pitch * 2.6, from: nil, pitch: pitch, last: last) == pitch * 3)
    }

    @Test("A flick carries the crate a few records at most, either way")
    func flickIsHeldToAFew() {
        let last = pitch * 30
        let reach = CrateRest.flingReach
        #expect(CrateRest.offset(for: pitch * 25, from: 10, pitch: pitch, last: last) == pitch * Double(10 + reach))
        #expect(CrateRest.offset(for: 0, from: 10, pitch: pitch, last: last) == pitch * Double(10 - reach))
        #expect(CrateRest.offset(for: pitch * 12, from: 10, pitch: pitch, last: last) == pitch * 12)
    }

    @Test("It never rests beyond the first or last record")
    func restsInsideTheRow() {
        let last = pitch * 4
        #expect(CrateRest.offset(for: -pitch * 3, from: 1, pitch: pitch, last: last) == 0)
        #expect(CrateRest.offset(for: pitch * 9, from: 3, pitch: pitch, last: last) == last)
        #expect(CrateRest.offset(for: pitch * 9, from: nil, pitch: pitch, last: last) == last)
    }

    @Test("A crate of one record always rests on it")
    func singleRecord() {
        #expect(CrateRest.offset(for: pitch * 0.8, from: 0, pitch: pitch, last: 0) == 0)
        #expect(CrateRest.offset(for: -pitch, from: 0, pitch: pitch, last: -12) == 0)
    }
}
