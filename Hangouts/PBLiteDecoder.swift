import Foundation

/* TODO: Support sharing the Coder with super. */

//
// MARK: PBLiteDecoder
//

///
/// Note: performs string numeric casting on FixedWidthInteger types.
public class PBLiteDecoder {
    
    ///
    public struct Options: OptionSet {
        public typealias RawValue = Int
        public var rawValue: Int
        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }
        
        ///
        public static let multipleRootContainers = Options(rawValue: 1 << 0)
        
        ///
        public static let primitiveRootValues = Options(rawValue: 1 << 1)
        
        // zeroindex
    }
    
    public let options: Options
    public init(options: Options = []) {
        self.options = options
    }
    
    private var root: DecoderContainer? = nil
    public func decode<T: Decodable>(_ value: Any) throws -> T {
        self.root = DecoderContainer(owner: self, codingPath: [], content: value)
        return try T(from: self.root!)
    }
    
    // Data-based wrapper...
    public func decode<T: Decodable>(data: Data) throws -> T? {
        guard let script = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Data corrupted."))
        }
        guard var parsed = PBLiteDecoder.sanitize(script) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Data corrupted: \(script)"))
        }
        parsed.remove(at: 0) // FIXME: for the header thing?
        return try self.decode(parsed) as T
    }
    
    /// Sanitize and decode JSON from a server PBLite response.
    /// Note: This assumes the output will always be an array.
    // Precompile the regex so we don't fiddle around with slow loading times.
    internal static func sanitize(_ string: String) -> [Any]? {
        let st = reg.stringByReplacingMatches(in: string, options: [], range: NSMakeRange(0, string.utf16.count), withTemplate: "$1null")
        return try! st.decodeJSON() as? [Any]
    }
    private static let reg = try! NSRegularExpression(pattern: "(?<=,|\\[)(\\s)*(?=,)", options: [])
    
    //
    // MARK: PBLiteDecoder -> KeyedContainer
    //
    
    ///
    private class KeyedContainer<Key: CodingKey>: KeyedDecodingChildContainer {
        
        var codingPath: [CodingKey]
        var children: [DecodingChildContainer] = []
        private let content: [Int: Any]
        
        let owner: PBLiteDecoder
        init(owner: PBLiteDecoder, codingPath: [CodingKey], content: [Any]) {
            self.owner = owner
            self.codingPath = codingPath
            self.content = KeyedContainer.transform(content)
        }
        
        //
        // MARK: PBLiteDecoder -> KeyedContainer -> Decoding
        //
        
        func matchesType<T: Decodable>(_: T.Type, forKey key: Key) -> Bool {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                print("\(key) was null!")
                return false
            }
            guard let _ = outerValue as? T else {
                print("\(key) was of type \(type(of: outerValue)) instead of \(T.self)")
                return false
            }
            return true
        }
        
        func matchesNumericType<T: Decodable & FixedWidthInteger>(_: T.Type, forKey key: Key) -> Bool {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                print("NUMERIC: \(key) was null!")
                return false
            }
            guard let _ = outerValue as? T else {
                if let innerValue = outerValue as? String, let _ = T(innerValue) {
                    print("NUMERIC: \(key) was of type \(type(of: outerValue)) instead of \(T.self)")
                    return false
                }
                return false
            }
            return true
        }
        
        func decodeNil(forKey key: Key) throws -> Bool {
            if let outerValue = self.content[key.value()], (outerValue is NSNull) {
                return true
            }
            return false
        }
        
        func decodeNumeric<T: Decodable & FixedWidthInteger>(forKey key: Key) throws -> T {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                let desc = "Expected type \(T.self) for \(key) but container stored nil."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            guard let value = outerValue as? T else {
                if let value2 = outerValue as? String, let value3 = T(value2) {
                    return value3
                }
                let desc = "Expected type \(T.self) for \(key) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            return value
        }
        
        func decodeValue<T: Decodable>(forKey key: Key) throws -> T {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                let desc = "Expected type \(T.self) for \(key) but container stored nil."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            guard let value = outerValue as? T else {
                let desc = "Expected type \(T.self) for \(key) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            return value
        }
        
        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                if "\(type)".starts(with: "Array<") {
                    return ([] as! T)
                }
                let desc = "Expected type \(T.self) for \(key) but container stored nil."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            return try T(from: DecoderContainer(owner: self.owner, codingPath: self.codingPath + [key], content: outerValue))
        }
        
        //
        // MARK: PBLiteDecoder -> KeyedContainer -> ChildContainer
        //
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                let desc = "No element matching key \(key) in the container."
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            guard let inside = outerValue as? [Any] else {
                let desc = "Expected type \(Array<Any>.self) for \(key) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(Array<Any>.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let container = KeyedContainer<NestedKey>(owner: self.owner, codingPath: self.codingPath + [key], content: inside)
            self.children.append(container)
            return KeyedDecodingContainer(container)
        }
        
        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            guard let outerValue = self.content[key.value()], !(outerValue is NSNull) else {
                let desc = "No element matching key \(key) in the container."
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            guard let inside = outerValue as? [Any] else {
                let desc = "Expected type \(Array<Any>.self) for \(key) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(Array<Any>.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let container = UnkeyedContainer(owner: self.owner, codingPath: self.codingPath + [key], content: inside)
            self.children.append(container)
            return container
        }
        
        func superDecoder() throws -> Decoder {
            let key = Key(intValue: 0)! // TODO: will this even work?
            return try self.superDecoder(forKey: key)
        }
        
        func superDecoder(forKey key: Key) throws -> Decoder {
            guard let inside = self.content[key.value()], !(inside is NSNull) else {
                let desc = "No superDecoder element found in the container."
                throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let container = DecoderContainer(owner: self.owner, codingPath: self.codingPath + [key], content: inside)
            self.children.append(container)
            return container
        }
        
        //
        // MARK: PBLiteDecoder -> KeyedContainer -> Misc
        //
        
        var allKeys: [Key] {
            return Array(self.content.keys).compactMap { Key(intValue: $0) }
        }
        
        func contains(_ key: Key) -> Bool {
            return self.content.keys.contains(key.value())
        }
        
        /// Convert between an Int-keyed Dictionary and Array.
        /// Note: k + 1 because message indexes start at 1.
        private static func transform(_ content: [Any]) -> [Int: Any] {
            var dicted: [Int: Any] = [:]
            for (k, v) in content.enumerated() {
                if case Optional<Any>.none = v {
                    // ignore nils
                } else if case Optional<Any>.some(let val) = v, !(val is NSNull) {
                    dicted[k + 1] = val
                } else if !(v is NSNull) {
                    dicted[k + 1] = v
                }
            }
            
            /// PBLite comes with some extras...
            if let extras = dicted[content.count] as? NSDictionary {
                dicted.removeValue(forKey: content.count)
                for (k, v) in extras {
                    let idx = Int(k as! String)!
                    dicted[idx] = v
                }
            }
            return dicted
        }
    }
    
    //
    // MARK: PBLiteDecoder -> UnkeyedContainer
    //
    
    /// TODO: Fix the NSNull stuff here
    private class UnkeyedContainer: UnkeyedDecodingChildContainer {
        private let content: [Any]
        var codingPath: [CodingKey]
        var count: Int? = nil
        var children: [DecodingChildContainer] = []
        var currentIndex: Int {
            return self.content.count - (self.count ?? 0)
        }
        
        let owner: PBLiteDecoder
        init(owner: PBLiteDecoder, codingPath: [CodingKey], content: [Any]) {
            self.owner = owner
            self.codingPath = codingPath
            self.content = content
            self.count = content.count
        }
        
        //
        // MARK: PBLiteDecoder -> UnkeyedContainer -> Decoding
        //
        
        func matchesType<T: Decodable>(_: T.Type) -> Bool {
            guard let count = self.count, count > 0 else {
                return false
            }
            let outerValue = self.content[self.content.count - count]
            guard let _ = outerValue as? T else {
                return false
            }
            return true
        }
        
        func matchesNumericType<T: Decodable & FixedWidthInteger>(_: T.Type) -> Bool {
            guard let count = self.count, count > 0 else {
                return false
            }
            let outerValue = self.content[self.content.count - count]
            guard let _ = outerValue as? T else {
                if let innerValue = outerValue as? String, let _ = T(innerValue) {
                    return false
                }
                return false
            }
            return true
        }
        
        func decodeNil() throws -> Bool {
            return (self.count ?? 0) == 0
        }
        
        func decodeNumeric<T: Decodable & FixedWidthInteger>() throws -> T {
            guard let count = self.count, count > 0 else {
                let desc = "Expected type \(T.self) but container had nothing left."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let outerValue = self.content[self.content.count - count]
            guard let value = outerValue as? T else {
                if let value2 = outerValue as? String, let value3 = T(value2) {
                    return value3
                }
                let desc = "Expected type \(T.self) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            self.count = count - 1 // decrement
            return value
        }
        
        func decodeValue<T: Decodable>() throws -> T {
            guard let count = self.count, count > 0 else {
                let desc = "Expected type \(T.self) but container had nothing left."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let outerValue = self.content[self.content.count - count]
            guard let value = outerValue as? T else {
                let desc = "Expected type \(T.self) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            self.count = count - 1 // decrement
            return value
        }
        
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            guard let count = self.count, count > 0 else {
                let desc = "Expected type \(T.self) but container had nothing left."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let outerValue = self.content[self.content.count - count]
            self.count = count - 1 // decrement
            return try T(from: DecoderContainer(owner: self.owner, codingPath: self.codingPath + [PBLiteKey(intValue: self.count ?? 0)!], content: outerValue))
        }
        
        //
        // MARK: PBLiteDecoder -> UnkeyedContainer -> ChildContainer
        //
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
            guard let count = self.count, count > 0 else {
                let desc = "No more elements remaining in the container."
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let outerValue = self.content[self.content.count - count]
            guard let inside = outerValue as? [Any] else {
                let desc = "Expected type \(Array<Any>.self) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(Array<Any>.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            
            let container = KeyedContainer<NestedKey>(owner: self.owner, codingPath: self.codingPath + [PBLiteKey(intValue: self.count ?? 0)!], content: inside)
            self.children.append(container)
            self.count = count - 1 // decrement
            return KeyedDecodingContainer(container)
        }
        
        func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            guard let count = self.count, count > 0 else {
                let desc = "No more elements remaining in the container."
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let outerValue = self.content[self.content.count - count]
            guard let inside = outerValue as? [Any] else {
                let desc = "Expected type \(Array<Any>.self) but container stored value \(String(reflecting: outerValue))."
                throw DecodingError.typeMismatch(Array<Any>.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            
            let container = UnkeyedContainer(owner: self.owner, codingPath: self.codingPath + [PBLiteKey(intValue: self.count ?? 0)!], content: inside)
            self.children.append(container)
            self.count = count - 1 // decrement
            return container
        }
        
        func superDecoder() throws -> Decoder {
            guard let count = self.count, count > 0 else {
                let desc = "No more elements remaining in the container."
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            let outerValue = self.content[self.content.count - count]
            let container = DecoderContainer(owner: self.owner, codingPath: self.codingPath + [PBLiteKey(intValue: self.count ?? 0)!], content: outerValue)
            self.children.append(container)
            self.count = count - 1 // decrement
            return container
        }
        
        //
        // MARK: PBLiteDecoder -> UnkeyedContainer -> Misc
        //
        
        var isAtEnd: Bool {
            return self.count == nil || self.count == 0
        }
    }
    
    //
    // MARK: PBLiteDecoder -> SingleValueContainer
    //
    
    ///
    private class SingleValueContainer: SingleValueDecodingChildContainer {
        private let content: Any
        fileprivate var children: [DecodingChildContainer] {
            get { return [] } set { }
        }
        var codingPath: [CodingKey] {
            return []
        }
        
        let owner: PBLiteDecoder
        init(owner: PBLiteDecoder, content: Any) {
            self.owner = owner
            self.content = content
        }
        
        //
        // MARK: PBLiteDecoder -> SingleValueContainer -> Decoding
        //
        
        func matchesType<T: Decodable>(_: T.Type) -> Bool {
            guard case Optional<Any>.some(let val) = self.content, !(val is NSNull) else {
                return false
            }
            guard let _ = self.content as? T else {
                //if let innerValue = outerValue as? String, let _ = T(innerValue) {
                //    return false
                //}
                return false
            }
            return true
        }
        
        func decodeNil() -> Bool {
            if case Optional<Any>.none = self.content {
                return true
            } else if case Optional<Any>.some(let val) = self.content, !(val is NSNull) {
                return false
            }
            return true // uh...?
        }
        
        func decodeNumeric<T: Decodable & FixedWidthInteger>() throws -> T {
            guard case Optional<Any>.some(let val) = self.content, !(val is NSNull) else {
                let desc = "Expected type \(T.self) but container stored nil."
                throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [], debugDescription: desc))
            }
            guard let value = self.content as? T else {
                if let value2 = self.content as? String, let value3 = T(value2) {
                    return value3
                }
                let desc = "Expected type \(T.self) but container stored value \(String(reflecting: self.content))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: [], debugDescription: desc))
            }
            return value
        }
        
        func decodeValue<T: Decodable>() throws -> T {
            guard case Optional<Any>.some(let val) = self.content, !(val is NSNull) else {
                let desc = "Expected type \(T.self) but container stored nil."
                throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [], debugDescription: desc))
            }
            guard let value = self.content as? T else {
                let desc = "Expected type \(T.self) but container stored value \(String(reflecting: self.content))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: [], debugDescription: desc))
            }
            return value
        }
        
        // TODO: should this be allowed?
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            guard case Optional<Any>.some(let val) = self.content, !(val is NSNull) else {
                let desc = "Expected type \(T.self) but container stored nil."
                throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [], debugDescription: desc))
            }
            guard let value = self.content as? [Any] else {
                let desc = "Expected type \(T.self) but container stored value \(String(reflecting: self.content))."
                throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: [], debugDescription: desc))
            }
            return try T(from: DecoderContainer(owner: self.owner, codingPath: [PBLiteKey(intValue: 0)!], content: value))
        }
    }
    
    //
    // MARK: PBLiteDecoder -> DecoderContainer
    //
    
    private class DecoderContainer: DecoderDecodingChildContainer {
        public var codingPath: [CodingKey]
        public var userInfo: [CodingUserInfoKey : Any] = [:]
        fileprivate let owner: PBLiteDecoder
        internal var children: [DecodingChildContainer] = []
        fileprivate var content: Any = Optional<Any>.none as Any
        
        fileprivate init(owner: PBLiteDecoder, codingPath: [CodingKey], content: Any) {
            self.owner = owner
            self.codingPath = codingPath
            self.content = content
        }
        
        //
        // MARK: PBLiteDecoder -> DecoderContainer -> ChildContainer
        //
        
        public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
            try! throwIfExists()
            guard let inside = self.content as? [Any] else {
                let desc = "This decoder's content could not support a keyed container."
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            
            let container = KeyedContainer<Key>(owner: self.owner, codingPath: self.codingPath, content: inside)
            self.children.append(container)
            return KeyedDecodingContainer(container)
        }
        
        public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
            try! throwIfExists()
            guard let inside = self.content as? [Any] else {
                let desc = "This decoder's content could not support an unkeyed container."
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
            
            let container = UnkeyedContainer(owner: self.owner, codingPath: self.codingPath, content: inside)
            self.children.append(container)
            return container
        }
        
        public func singleValueContainer() throws -> SingleValueDecodingContainer {
            try! throwIfExists()
            let container = SingleValueContainer(owner: self.owner, content: self.content)
            self.children.append(container)
            return container
        }
        
        //
        // MARK: PBLiteDecoder -> DecoderContainer -> Misc
        //
        
        private func throwIfExists() throws {
            if self.children.count > 0 && !self.owner.options.contains(.multipleRootContainers) {
                let desc = "This decoder is not configured to support multiple root containers."
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: desc))
            }
        }
    }
}

//
// MARK: Helpers
//

internal struct PBLiteKey: CodingKey {
    init?(intValue: Int) {
        self.intValue = intValue
    }
    init?(stringValue: String) {
        return nil
    }
    
    var intValue: Int?
    var stringValue: String {
        return "\(self.intValue ?? 0)"
    }
}

///
fileprivate extension CodingKey {
    func value() -> String {
        return self.stringValue
    }
    func value() -> Int {
        if let i = self.intValue { return i }
        fatalError("requires an integer coding key")
    }
}

///
fileprivate protocol DecodingChildContainer {}

// TODO: Type matching first before decodeIfPresent:
//CodingKeys(stringValue: "phoneData", intValue: 7) was of type __NSArrayM instead of ClientPhoneData
//CodingKeys(stringValue: "configurationBitType", intValue: 1) was of type __NSCFNumber instead of ClientConfigurationBitType

fileprivate protocol DecoderDecodingChildContainer: Decoder, DecodingChildContainer {}
fileprivate protocol KeyedDecodingChildContainer: KeyedDecodingContainerProtocol, DecodingChildContainer {
    func matchesType<T: Decodable>(_: T.Type, forKey key: Key) -> Bool
    func matchesNumericType<T: Decodable & FixedWidthInteger>(_: T.Type, forKey key: Key) -> Bool
    //func decodeNil(forKey key: Self.Key) throws -> Bool
    func decodeValue<T: Decodable>(forKey: Key) throws -> T
    func decodeNumeric<T: Decodable & FixedWidthInteger>(forKey: Key) throws -> T
}
fileprivate protocol UnkeyedDecodingChildContainer: UnkeyedDecodingContainer, DecodingChildContainer {
    func matchesType<T: Decodable>(_: T.Type) -> Bool
    func matchesNumericType<T: Decodable & FixedWidthInteger>(_: T.Type) -> Bool
    //mutating func decodeNil() throws -> Bool
    mutating func decodeValue<T: Decodable>() throws -> T
    mutating func decodeNumeric<T: Decodable & FixedWidthInteger>() throws -> T
}
fileprivate protocol SingleValueDecodingChildContainer: SingleValueDecodingContainer, DecodingChildContainer {
    //func decodeNil() -> Bool
    func decodeValue<T: Decodable>() throws -> T
    func decodeNumeric<T: Decodable & FixedWidthInteger>() throws -> T
}

fileprivate extension KeyedDecodingChildContainer {
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        return try decodeValue(forKey: key)
    }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        return try decodeNumeric(forKey: key)
    }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        return try decodeValue(forKey: key)
    }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        return try decodeValue(forKey: key)
    }
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        return try decodeValue(forKey: key)
    }
    
    //
    //
    //
    /*
    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesType(type, forKey: key) else { return nil }
        return try decodeValue(forKey: key)
    }
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesNumericType(type, forKey: key) else { return nil }
        return try decodeNumeric(forKey: key)
    }
    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesType(type, forKey: key) else { return nil }
        return try decodeValue(forKey: key)
    }
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesType(type, forKey: key) else { return nil }
        return try decodeValue(forKey: key)
    }
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesType(type, forKey: key) else { return nil }
        return try decodeValue(forKey: key)
    }
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard try self.contains(key) && !self.decodeNil(forKey: key) else { return nil }
        guard self.matchesType(type, forKey: key) else { return nil }
        return try decodeValue(forKey: key)
    }*/
}

fileprivate extension UnkeyedDecodingChildContainer {
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        return try decodeValue()
    }
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: UInt.Type) throws -> UInt {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try decodeNumeric()
    }
    
    mutating func decode(_ type: Float.Type) throws -> Float {
        return try decodeValue()
    }
    
    mutating func decode(_ type: Double.Type) throws -> Double {
        return try decodeValue()
    }
    
    mutating func decode(_ type: String.Type) throws -> String {
        return try decodeValue()
    }
    
    //
    //
    //
    /*
    mutating func decodeIfPresent(_ type: Bool.Type) throws -> Bool? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Int.Type) throws -> Int? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Int8.Type) throws -> Int8? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Int16.Type) throws -> Int16? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Int32.Type) throws -> Int32? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Int64.Type) throws -> Int64? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: UInt.Type) throws -> UInt? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesNumericType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Float.Type) throws -> Float? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: Double.Type) throws -> Double? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent(_ type: String.Type) throws -> String? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesType(type) else { return nil }
        return try decodeValue()
    }
    mutating func decodeIfPresent<T: Decodable>(_ type: T.Type) throws -> T? {
        guard try !self.isAtEnd && !self.decodeNil() else { return nil }
        guard self.matchesType(type) else { return nil }
        return try decodeValue()
    }*/
}

fileprivate extension SingleValueDecodingChildContainer {
    func decode(_ type: Bool.Type) throws -> Bool {
        return try decodeValue()
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        return try decodeNumeric()
    }
    
    func decode(_ type: Int8.Type) throws -> Int8 {
        return try decodeNumeric()
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        return try decodeNumeric()
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        return try decodeNumeric()
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        return try decodeNumeric()
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        return try decodeNumeric()
    }
    
    func decode(_ type: UInt8.Type) throws -> UInt8 {
        return try decodeNumeric()
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        return try decodeNumeric()
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        return try decodeNumeric()
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        return try decodeNumeric()
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        return try decodeValue()
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        return try decodeValue()
    }
    
    func decode(_ type: String.Type) throws -> String {
        return try decodeValue()
    }
}
