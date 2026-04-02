import Testing
@testable import Mangox

struct RingBufferTests {

    @Test func appendAndAverageBeforeFull() {
        var buffer = RingBuffer<Int>(capacity: 5)

        buffer.append(100)
        buffer.append(200)
        buffer.append(300)

        #expect(buffer.currentCount == 3)
        #expect(buffer.values == [100, 200, 300])
        #expect(buffer.average == 200)
    }

    @Test func overflowKeepsMostRecentValues() {
        var buffer = RingBuffer<Int>(capacity: 3)

        buffer.append(10)
        buffer.append(20)
        buffer.append(30)
        buffer.append(40)

        #expect(buffer.isFull)
        #expect(buffer.values == [20, 30, 40])
        #expect(buffer.average == 30)
    }

    @Test func resetClearsBuffer() {
        var buffer = RingBuffer<Int>(capacity: 2)

        buffer.append(5)
        buffer.append(15)
        buffer.reset()

        #expect(buffer.isEmpty)
        #expect(buffer.currentCount == 0)
        #expect(buffer.values.isEmpty)
        #expect(buffer.average == 0)
    }
}
