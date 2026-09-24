import Foundation

typealias JSONObject = [String: Any]
extension Dictionary where Key == String, Value == Any {
  func dictionary(_ key: String) -> JSONObject? { self[key] as? JSONObject }
  func array(_ key: String) -> [Any]? { self[key] as? [Any] }
  func string(_ key: String) -> String? {
    guard let v = self[key] as? String, !v.isEmpty else { return nil }
    return v
  }
  func bool(_ key: String) -> Bool? { self[key] as? Bool }
  func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
  func int64(_ key: String) -> Int64? { (self[key] as? NSNumber)?.int64Value }
}
