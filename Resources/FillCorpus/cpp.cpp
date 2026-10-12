#include <iostream>
#include <vector>
#include <string>
#include <map>
#include <unordered_map>
#include <set>
#include <algorithm>
#include <numeric>
#include <memory>
#include <fstream>
#include <sstream>
#include <stdexcept>

using namespace std;

int factorial(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

int fibonacci(int n) {
    if (n <= 1) {
        return n;
    }
    return fibonacci(n - 1) + fibonacci(n - 2);
}

bool isPrime(int n) {
    if (n < 2) {
        return false;
    }
    for (int i = 2; i * i <= n; i++) {
        if (n % i == 0) {
            return false;
        }
    }
    return true;
}

int sum(const vector<int>& numbers) {
    return accumulate(numbers.begin(), numbers.end(), 0);
}

double average(const vector<int>& numbers) {
    if (numbers.empty()) {
        return 0.0;
    }
    return static_cast<double>(sum(numbers)) / numbers.size();
}

int findMax(const vector<int>& numbers) {
    return *max_element(numbers.begin(), numbers.end());
}

void printVector(const vector<int>& numbers) {
    for (int number : numbers) {
        cout << number << " ";
    }
    cout << endl;
}

string reverseString(string str) {
    reverse(str.begin(), str.end());
    return str;
}

bool isPalindrome(const string& str) {
    int left = 0;
    int right = str.size() - 1;
    while (left < right) {
        if (str[left] != str[right]) {
            return false;
        }
        left++;
        right--;
    }
    return true;
}

vector<string> split(const string& str, char delimiter) {
    vector<string> tokens;
    stringstream ss(str);
    string token;
    while (getline(ss, token, delimiter)) {
        tokens.push_back(token);
    }
    return tokens;
}

int binarySearch(const vector<int>& arr, int target) {
    int low = 0;
    int high = arr.size() - 1;
    while (low <= high) {
        int mid = low + (high - low) / 2;
        if (arr[mid] == target) {
            return mid;
        } else if (arr[mid] < target) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return -1;
}

void bubbleSort(vector<int>& arr) {
    int n = arr.size();
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                swap(arr[j], arr[j + 1]);
            }
        }
    }
}

map<string, int> countWords(const string& text) {
    map<string, int> counts;
    stringstream ss(text);
    string word;
    while (ss >> word) {
        counts[word]++;
    }
    return counts;
}

vector<string> readLines(const string& filename) {
    vector<string> lines;
    ifstream file(filename);
    if (!file.is_open()) {
        throw runtime_error("Could not open " + filename);
    }
    string line;
    while (getline(file, line)) {
        lines.push_back(line);
    }
    return lines;
}

void writeFile(const string& filename, const string& content) {
    ofstream file(filename);
    file << content << endl;
}

template <typename T>
T maxOf(const vector<T>& values) {
    T best = values[0];
    for (const T& value : values) {
        if (value > best) {
            best = value;
        }
    }
    return best;
}

class Shape {
public:
    virtual ~Shape() = default;
    virtual double area() const = 0;
    virtual string name() const = 0;
};

class Circle : public Shape {
public:
    explicit Circle(double radius) : radius(radius) {}

    double area() const override {
        return 3.14159265358979 * radius * radius;
    }

    string name() const override {
        return "Circle";
    }

private:
    double radius;
};

class Rectangle : public Shape {
public:
    Rectangle(double width, double height) : width(width), height(height) {}

    double area() const override {
        return width * height;
    }

    string name() const override {
        return "Rectangle";
    }

private:
    double width;
    double height;
};

class BankAccount {
public:
    BankAccount(string owner, double balance = 0.0) : owner(move(owner)), balance(balance) {}

    void deposit(double amount) {
        if (amount <= 0) {
            throw invalid_argument("Deposit must be positive");
        }
        balance += amount;
    }

    void withdraw(double amount) {
        if (amount > balance) {
            throw runtime_error("Insufficient funds");
        }
        balance -= amount;
    }

    double getBalance() const {
        return balance;
    }

    const string& getOwner() const {
        return owner;
    }

private:
    string owner;
    double balance;
};

template <typename T>
class Stack {
public:
    void push(const T& item) {
        items.push_back(item);
    }

    T pop() {
        if (items.empty()) {
            throw out_of_range("Stack is empty");
        }
        T item = items.back();
        items.pop_back();
        return item;
    }

    bool empty() const {
        return items.empty();
    }

    size_t size() const {
        return items.size();
    }

private:
    vector<T> items;
};

int main() {
    vector<int> numbers = {5, 3, 8, 1, 9, 2};

    cout << "Original: ";
    printVector(numbers);

    sort(numbers.begin(), numbers.end());
    cout << "Sorted: ";
    printVector(numbers);

    cout << "Sum: " << sum(numbers) << endl;
    cout << "Average: " << average(numbers) << endl;
    cout << "Max: " << findMax(numbers) << endl;

    for (int i = 0; i < 10; i++) {
        cout << i << "! = " << factorial(i) << endl;
    }

    for (size_t i = 0; i < numbers.size(); i++) {
        cout << i << ": " << numbers[i] << endl;
    }

    map<string, int> ages = {{"Alice", 30}, {"Bob", 25}};
    for (const auto& [name, age] : ages) {
        cout << name << " is " << age << endl;
    }

    vector<unique_ptr<Shape>> shapes;
    shapes.push_back(make_unique<Circle>(2.0));
    shapes.push_back(make_unique<Rectangle>(3.0, 4.0));
    for (const auto& shape : shapes) {
        cout << shape->name() << ": " << shape->area() << endl;
    }

    string name;
    cout << "Enter your name: ";
    getline(cin, name);
    cout << "Hello, " << name << "!" << endl;

    try {
        BankAccount account("Ada", 100.0);
        account.withdraw(500.0);
    } catch (const exception& e) {
        cerr << "Error: " << e.what() << endl;
    }

    auto evens = count_if(numbers.begin(), numbers.end(), [](int n) { return n % 2 == 0; });
    cout << "Even numbers: " << evens << endl;

    return 0;
}
