import Foundation
import SwiftUI

func fibonacci(_ n: Int) -> Int {
    if n <= 1 {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

func factorial(_ n: Int) -> Int {
    if n <= 1 {
        return 1
    }
    return n * factorial(n - 1)
}

func isPrime(_ n: Int) -> Bool {
    if n < 2 {
        return false
    }
    var i = 2
    while i * i <= n {
        if n % i == 0 {
            return false
        }
        i += 1
    }
    return true
}

func gcd(_ a: Int, _ b: Int) -> Int {
    var a = a, b = b
    while b != 0 {
        (a, b) = (b, a % b)
    }
    return a
}

func sum(_ numbers: [Int]) -> Int {
    numbers.reduce(0, +)
}

func average(_ numbers: [Double]) -> Double {
    guard !numbers.isEmpty else { return 0 }
    return numbers.reduce(0, +) / Double(numbers.count)
}

func reverseString(_ text: String) -> String {
    String(text.reversed())
}

func isPalindrome(_ text: String) -> Bool {
    let cleaned = text.lowercased().filter { $0.isLetter || $0.isNumber }
    return cleaned == String(cleaned.reversed())
}

func countWords(_ text: String) -> [String: Int] {
    var counts: [String: Int] = [:]
    for word in text.lowercased().split(separator: " ") {
        counts[String(word), default: 0] += 1
    }
    return counts
}

func binarySearch(_ array: [Int], target: Int) -> Int? {
    var low = 0
    var high = array.count - 1
    while low <= high {
        let mid = (low + high) / 2
        if array[mid] == target {
            return mid
        } else if array[mid] < target {
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    return nil
}

func bubbleSort(_ array: [Int]) -> [Int] {
    var array = array
    for i in 0..<array.count {
        for j in 0..<array.count - i - 1 {
            if array[j] > array[j + 1] {
                array.swapAt(j, j + 1)
            }
        }
    }
    return array
}

func readFile(at path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func writeFile(_ content: String, to path: String) throws {
    try content.write(toFile: path, atomically: true, encoding: .utf8)
}

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
}

enum NetworkError: Error {
    case invalidURL
    case badResponse(Int)
}

func fetchUsers() async throws -> [User] {
    guard let url = URL(string: "https://jsonplaceholder.typicode.com/users") else {
        throw NetworkError.invalidURL
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw NetworkError.badResponse(http.statusCode)
    }
    return try JSONDecoder().decode([User].self, from: data)
}

struct Point {
    var x: Double
    var y: Double

    func distance(to other: Point) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

class BankAccount {
    let owner: String
    private(set) var balance: Double

    init(owner: String, balance: Double = 0) {
        self.owner = owner
        self.balance = balance
    }

    func deposit(_ amount: Double) {
        guard amount > 0 else { return }
        balance += amount
    }

    func withdraw(_ amount: Double) -> Bool {
        guard amount <= balance else { return false }
        balance -= amount
        return true
    }
}

struct Stack<Element> {
    private var items: [Element] = []

    mutating func push(_ item: Element) {
        items.append(item)
    }

    mutating func pop() -> Element? {
        items.popLast()
    }

    func peek() -> Element? {
        items.last
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var count: Int {
        items.count
    }
}

protocol Shape {
    func area() -> Double
}

struct Circle: Shape {
    let radius: Double

    func area() -> Double {
        .pi * radius * radius
    }
}

struct Rectangle: Shape {
    let width: Double
    let height: Double

    func area() -> Double {
        width * height
    }
}

enum Direction: String, CaseIterable {
    case north, south, east, west
}

func describe(_ direction: Direction) -> String {
    switch direction {
    case .north:
        return "Up"
    case .south:
        return "Down"
    case .east:
        return "Right"
    case .west:
        return "Left"
    }
}

let numbers = [5, 3, 8, 1, 9, 2]
let doubled = numbers.map { $0 * 2 }
let evens = numbers.filter { $0 % 2 == 0 }
let total = numbers.reduce(0, +)
let sorted = numbers.sorted()

for number in numbers {
    print(number)
}

for (index, value) in numbers.enumerated() {
    print("\(index): \(value)")
}

for i in 0..<10 {
    print("\(i)! = \(factorial(i))")
}

let ages = ["Alice": 30, "Bob": 25]
for (name, age) in ages {
    print("\(name) is \(age)")
}

if let index = binarySearch(sorted, target: 8) {
    print("Found at \(index)")
} else {
    print("Not found")
}

struct ContentView: View {
    @State private var count = 0
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Hello, \(name.isEmpty ? "world" : name)!")
                .font(.title)
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Count: \(count)")
            Button("Increment") {
                count += 1
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct UserListView: View {
    @State private var users: [User] = []

    var body: some View {
        List(users) { user in
            VStack(alignment: .leading) {
                Text(user.name)
                    .font(.headline)
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            users = (try? await fetchUsers()) ?? []
        }
    }
}
