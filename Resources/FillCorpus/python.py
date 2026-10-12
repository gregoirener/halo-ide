import os
import sys
import json
import csv
import math
import random
import time
import logging
import argparse
from pathlib import Path
from collections import Counter, defaultdict, deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from functools import lru_cache, wraps
from typing import Any, Dict, List, Optional, Tuple


def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)


def fibonacci_iterative(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


@lru_cache(maxsize=None)
def fibonacci_memo(n):
    if n < 2:
        return n
    return fibonacci_memo(n - 1) + fibonacci_memo(n - 2)


def factorial(n):
    if n == 0:
        return 1
    return n * factorial(n - 1)


def factorial_iterative(n):
    result = 1
    for i in range(2, n + 1):
        result *= i
    return result


def is_prime(n):
    if n < 2:
        return False
    for i in range(2, int(math.sqrt(n)) + 1):
        if n % i == 0:
            return False
    return True


def primes_up_to(limit):
    sieve = [True] * (limit + 1)
    sieve[0] = sieve[1] = False
    for i in range(2, int(limit ** 0.5) + 1):
        if sieve[i]:
            for j in range(i * i, limit + 1, i):
                sieve[j] = False
    return [i for i, prime in enumerate(sieve) if prime]


def gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def lcm(a, b):
    return a * b // gcd(a, b)


def is_even(n):
    return n % 2 == 0


def sum_list(numbers):
    total = 0
    for number in numbers:
        total += number
    return total


def average(numbers):
    if not numbers:
        return 0
    return sum(numbers) / len(numbers)


def find_max(numbers):
    largest = numbers[0]
    for number in numbers:
        if number > largest:
            largest = number
    return largest


def find_min(numbers):
    smallest = numbers[0]
    for number in numbers:
        if number < smallest:
            smallest = number
    return smallest


def count_occurrences(items, target):
    count = 0
    for item in items:
        if item == target:
            count += 1
    return count


def reverse_string(s):
    return s[::-1]


def is_palindrome(s):
    cleaned = "".join(c.lower() for c in s if c.isalnum())
    return cleaned == cleaned[::-1]


def count_vowels(text):
    vowels = "aeiouAEIOU"
    return sum(1 for char in text if char in vowels)


def word_count(text):
    counts = {}
    for word in text.lower().split():
        counts[word] = counts.get(word, 0) + 1
    return counts


def capitalize_words(sentence):
    return " ".join(word.capitalize() for word in sentence.split())


def remove_duplicates(items):
    seen = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def flatten(nested):
    result = []
    for item in nested:
        if isinstance(item, list):
            result.extend(flatten(item))
        else:
            result.append(item)
    return result


def chunk(items, size):
    return [items[i:i + size] for i in range(0, len(items), size)]


def two_sum(nums, target):
    seen = {}
    for i, num in enumerate(nums):
        complement = target - num
        if complement in seen:
            return [seen[complement], i]
        seen[num] = i
    return []


def binary_search(arr, target):
    low, high = 0, len(arr) - 1
    while low <= high:
        mid = (low + high) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            low = mid + 1
        else:
            high = mid - 1
    return -1


def linear_search(arr, target):
    for i, value in enumerate(arr):
        if value == target:
            return i
    return -1


def bubble_sort(arr):
    n = len(arr)
    for i in range(n):
        for j in range(0, n - i - 1):
            if arr[j] > arr[j + 1]:
                arr[j], arr[j + 1] = arr[j + 1], arr[j]
    return arr


def selection_sort(arr):
    for i in range(len(arr)):
        min_index = i
        for j in range(i + 1, len(arr)):
            if arr[j] < arr[min_index]:
                min_index = j
        arr[i], arr[min_index] = arr[min_index], arr[i]
    return arr


def insertion_sort(arr):
    for i in range(1, len(arr)):
        key = arr[i]
        j = i - 1
        while j >= 0 and arr[j] > key:
            arr[j + 1] = arr[j]
            j -= 1
        arr[j + 1] = key
    return arr


def merge_sort(arr):
    if len(arr) <= 1:
        return arr
    mid = len(arr) // 2
    left = merge_sort(arr[:mid])
    right = merge_sort(arr[mid:])
    return merge(left, right)


def merge(left, right):
    result = []
    i = j = 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            result.append(left[i])
            i += 1
        else:
            result.append(right[j])
            j += 1
    result.extend(left[i:])
    result.extend(right[j:])
    return result


def quick_sort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    middle = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return quick_sort(left) + middle + quick_sort(right)


def fizzbuzz(n):
    for i in range(1, n + 1):
        if i % 15 == 0:
            print("FizzBuzz")
        elif i % 3 == 0:
            print("Fizz")
        elif i % 5 == 0:
            print("Buzz")
        else:
            print(i)


def celsius_to_fahrenheit(celsius):
    return celsius * 9 / 5 + 32


def fahrenheit_to_celsius(fahrenheit):
    return (fahrenheit - 32) * 5 / 9


def matrix_multiply(a, b):
    rows, cols, inner = len(a), len(b[0]), len(b)
    result = [[0] * cols for _ in range(rows)]
    for i in range(rows):
        for j in range(cols):
            for k in range(inner):
                result[i][j] += a[i][k] * b[k][j]
    return result


def transpose(matrix):
    return [list(row) for row in zip(*matrix)]


def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_file(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f]


def append_line(path, line):
    with open(path, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return list(reader)


def write_csv(path, rows, fieldnames):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def list_files(directory, extension=".py"):
    return [p for p in Path(directory).rglob(f"*{extension}") if p.is_file()]


def get_json(url):
    import requests
    response = requests.get(url, timeout=10)
    response.raise_for_status()
    return response.json()


def post_json(url, payload):
    import requests
    response = requests.post(url, json=payload, timeout=10)
    response.raise_for_status()
    return response.json()


def timer(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"{func.__name__} took {elapsed:.3f}s")
        return result
    return wrapper


def retry(times=3, delay=1.0):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(times):
                try:
                    return func(*args, **kwargs)
                except Exception as error:
                    if attempt == times - 1:
                        raise
                    print(f"Attempt {attempt + 1} failed: {error}")
                    time.sleep(delay)
        return wrapper
    return decorator


def get_number(prompt):
    while True:
        try:
            return int(input(prompt))
        except ValueError:
            print("Please enter a valid number.")


def guess_the_number():
    secret = random.randint(1, 100)
    attempts = 0
    while True:
        guess = get_number("Guess a number between 1 and 100: ")
        attempts += 1
        if guess < secret:
            print("Too low!")
        elif guess > secret:
            print("Too high!")
        else:
            print(f"Correct! You found it in {attempts} attempts.")
            break


def bfs(graph, start):
    visited = set([start])
    queue = deque([start])
    order = []
    while queue:
        node = queue.popleft()
        order.append(node)
        for neighbor in graph[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(neighbor)
    return order


def dfs(graph, start, visited=None):
    if visited is None:
        visited = set()
    visited.add(start)
    for neighbor in graph[start]:
        if neighbor not in visited:
            dfs(graph, neighbor, visited)
    return visited


class Stack:
    def __init__(self):
        self.items = []

    def push(self, item):
        self.items.append(item)

    def pop(self):
        if self.is_empty():
            raise IndexError("pop from empty stack")
        return self.items.pop()

    def peek(self):
        return self.items[-1]

    def is_empty(self):
        return len(self.items) == 0

    def size(self):
        return len(self.items)


class Queue:
    def __init__(self):
        self.items = deque()

    def enqueue(self, item):
        self.items.append(item)

    def dequeue(self):
        return self.items.popleft()

    def is_empty(self):
        return len(self.items) == 0

    def __len__(self):
        return len(self.items)


class Node:
    def __init__(self, value):
        self.value = value
        self.next = None


class LinkedList:
    def __init__(self):
        self.head = None

    def append(self, value):
        new_node = Node(value)
        if self.head is None:
            self.head = new_node
            return
        current = self.head
        while current.next:
            current = current.next
        current.next = new_node

    def __iter__(self):
        current = self.head
        while current:
            yield current.value
            current = current.next

    def __repr__(self):
        return " -> ".join(str(value) for value in self)


class BankAccount:
    def __init__(self, owner, balance=0):
        self.owner = owner
        self.balance = balance

    def deposit(self, amount):
        if amount <= 0:
            raise ValueError("Deposit amount must be positive")
        self.balance += amount
        return self.balance

    def withdraw(self, amount):
        if amount > self.balance:
            raise ValueError("Insufficient funds")
        self.balance -= amount
        return self.balance

    def __str__(self):
        return f"{self.owner}: ${self.balance:.2f}"


class Animal:
    def __init__(self, name):
        self.name = name

    def speak(self):
        raise NotImplementedError

    def __str__(self):
        return f"{self.__class__.__name__}({self.name})"


class Dog(Animal):
    def speak(self):
        return f"{self.name} says Woof!"


class Cat(Animal):
    def speak(self):
        return f"{self.name} says Meow!"


@dataclass
class Point:
    x: float
    y: float

    def distance_to(self, other):
        return math.hypot(self.x - other.x, self.y - other.y)


@dataclass
class Person:
    name: str
    age: int
    email: str = ""

    def is_adult(self):
        return self.age >= 18


@dataclass
class Rectangle:
    width: float
    height: float

    def area(self):
        return self.width * self.height

    def perimeter(self):
        return 2 * (self.width + self.height)


def setup_logging(level=logging.INFO):
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    return logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description="Process some files.")
    parser.add_argument("path", help="file or folder to process")
    parser.add_argument("-v", "--verbose", action="store_true", help="print more output")
    parser.add_argument("-n", "--count", type=int, default=10, help="number of items")
    return parser.parse_args()


def main():
    args = parse_args()
    numbers = [5, 3, 8, 1, 9, 2]
    print(f"Sorted: {sorted(numbers)}")
    print(f"Max: {max(numbers)}, Min: {min(numbers)}")
    print(f"Average: {average(numbers):.2f}")
    for index, value in enumerate(numbers):
        print(f"{index}: {value}")
    squares = [n ** 2 for n in numbers]
    evens = [n for n in numbers if n % 2 == 0]
    print(squares, evens)
    scores = {"alice": 90, "bob": 75, "carol": 85}
    for name, score in scores.items():
        print(f"{name}: {score}")
    best = max(scores, key=scores.get)
    print(f"Best: {best}")
    words = ["apple", "banana", "cherry"]
    for word in sorted(words, key=len):
        print(word.upper())
    counter = Counter("mississippi")
    print(counter.most_common(3))
    groups = defaultdict(list)
    for word in words:
        groups[word[0]].append(word)
    try:
        result = 10 / 0
    except ZeroDivisionError as error:
        print(f"Error: {error}")
    finally:
        print("Done")
    now = datetime.now()
    print(now.strftime("%Y-%m-%d %H:%M:%S"))
    tomorrow = now + timedelta(days=1)
    print(tomorrow.date())


if __name__ == "__main__":
    main()


import unittest


class TestMath(unittest.TestCase):
    def test_factorial(self):
        self.assertEqual(factorial(5), 120)

    def test_is_prime(self):
        self.assertTrue(is_prime(7))
        self.assertFalse(is_prime(8))

    def test_reverse_string(self):
        self.assertEqual(reverse_string("abc"), "cba")


if __name__ == "__main__":
    unittest.main()


async def fetch(session, url):
    async with session.get(url) as response:
        return await response.json()


async def fetch_all(urls):
    import aiohttp
    import asyncio
    async with aiohttp.ClientSession() as session:
        tasks = [fetch(session, url) for url in urls]
        return await asyncio.gather(*tasks)


def plot_values(values):
    import matplotlib.pyplot as plt
    plt.figure(figsize=(8, 4))
    plt.plot(values, marker="o")
    plt.title("Values")
    plt.xlabel("Index")
    plt.ylabel("Value")
    plt.grid(True)
    plt.show()


def load_dataframe(path):
    import pandas as pd
    df = pd.read_csv(path)
    print(df.head())
    print(df.describe())
    return df


def train_model(X, y):
    from sklearn.model_selection import train_test_split
    from sklearn.linear_model import LinearRegression
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    model = LinearRegression()
    model.fit(X_train, y_train)
    score = model.score(X_test, y_test)
    print(f"R^2: {score:.3f}")
    return model


def create_app():
    from flask import Flask, jsonify, request
    app = Flask(__name__)

    @app.route("/")
    def index():
        return jsonify({"message": "Hello, world!"})

    @app.route("/items", methods=["POST"])
    def create_item():
        data = request.get_json()
        return jsonify(data), 201

    return app
