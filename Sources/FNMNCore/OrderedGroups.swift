import Foundation

enum OrderedGroups {
    struct Group<Element> {
        let key: String
        let name: String
        let items: [Element]
    }

    static func of<Element>(
        _ items: [Element], startingWith keys: [String] = [], by group: (Element) -> (key: String, name: String)?
    ) -> [Group<Element>] {
        var order = keys
        var seen = Set(keys)
        var names: [String: String] = [:]
        var members: [String: [Element]] = [:]
        for item in items {
            guard let (key, name) = group(item) else {
                continue
            }
            if seen.insert(key).inserted {
                order.append(key)
            }
            names[key] = name
            members[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let items = members[key] else {
                return nil
            }
            return Group(key: key, name: names[key] ?? key, items: items)
        }
    }
}
