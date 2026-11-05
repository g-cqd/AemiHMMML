import Testing

@testable import AemiTOML

@Suite("Byte classes")
struct ByteClassTests {
    @Test("each mask is exactly its bytes, and nothing at or above 0x80")
    func masks() {
        let bare = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
        let token = bare + Array("+.:".utf8)
        for byte in UInt8.min ... UInt8.max {
            #expect(TOMLParser.isBareKeyByte(byte) == bare.contains(byte), "\(byte)")
            #expect(TOMLParser.isTokenByte(byte) == token.contains(byte), "\(byte)")
        }
        #expect(ByteClass.masks(bare) == (0x03FF_2000_0000_0000, 0x07FF_FFFE_87FF_FFFE))
    }
}
