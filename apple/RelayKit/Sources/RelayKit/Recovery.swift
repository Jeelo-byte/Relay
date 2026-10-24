import Foundation
import CryptoKit
public enum RecoveryCode {
    static let alphabet=Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let checks=Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ*~$=U")
    public static func generate()->String {let chars=RelayCrypto.random(39).map {alphabet[Int($0)&31]};let c=String(chars)+String(checks[checksum(chars)]);return stride(from:0,to:40,by:5).map {String(Array(c)[$0..<$0+5])}.joined(separator:"-")}
    static func checksum(_ chars:[Character])->Int {chars.reduce(0){($0*32+(alphabet.firstIndex(of:$1) ?? 0))%37}}
    public static func normalize(_ code:String)->String {code.uppercased().replacingOccurrences(of:"O",with:"0").replacingOccurrences(of:"I",with:"1").replacingOccurrences(of:"L",with:"1").filter{!$0.isWhitespace && $0 != "-"}}
    public static func valid(_ code:String)->Bool {let c=Array(normalize(code));return c.count==40 && c.prefix(39).allSatisfy{alphabet.contains($0)} && c[39]==checks[checksum(Array(c.prefix(39)))]}
    public static func key(_ code:String)->Data? {guard valid(code) else {return nil};return RelayCrypto.hkdf(Data(normalize(code).prefix(39).utf8),label:"relay/v1/recovery-kek")}
    public static func proof(key:Data,account:UUID)->Data {Data(HMAC<SHA256>.authenticationCode(for:Data("relay/v1/recovery-proof|\(account.uuidString.lowercased())".utf8),using:SymmetricKey(data:key)))}
}
