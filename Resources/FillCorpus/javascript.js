const fs = require("fs");
const path = require("path");
const http = require("http");

function fibonacci(n) {
  if (n <= 1) {
    return n;
  }
  return fibonacci(n - 1) + fibonacci(n - 2);
}

function factorial(n) {
  if (n === 0) {
    return 1;
  }
  return n * factorial(n - 1);
}

function isPrime(n) {
  if (n < 2) {
    return false;
  }
  for (let i = 2; i <= Math.sqrt(n); i++) {
    if (n % i === 0) {
      return false;
    }
  }
  return true;
}

function gcd(a, b) {
  while (b !== 0) {
    [a, b] = [b, a % b];
  }
  return a;
}

function sum(numbers) {
  let total = 0;
  for (const number of numbers) {
    total += number;
  }
  return total;
}

function average(numbers) {
  if (numbers.length === 0) {
    return 0;
  }
  return numbers.reduce((acc, n) => acc + n, 0) / numbers.length;
}

function findMax(numbers) {
  let max = numbers[0];
  for (let i = 1; i < numbers.length; i++) {
    if (numbers[i] > max) {
      max = numbers[i];
    }
  }
  return max;
}

function findMin(numbers) {
  return Math.min(...numbers);
}

function reverseString(str) {
  return str.split("").reverse().join("");
}

function isPalindrome(str) {
  const cleaned = str.toLowerCase().replace(/[^a-z0-9]/g, "");
  return cleaned === cleaned.split("").reverse().join("");
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function countWords(text) {
  const counts = {};
  for (const word of text.toLowerCase().split(/\s+/)) {
    counts[word] = (counts[word] || 0) + 1;
  }
  return counts;
}

function unique(items) {
  return [...new Set(items)];
}

function flatten(arr) {
  return arr.reduce((acc, item) => acc.concat(Array.isArray(item) ? flatten(item) : item), []);
}

function chunk(arr, size) {
  const result = [];
  for (let i = 0; i < arr.length; i += size) {
    result.push(arr.slice(i, i + size));
  }
  return result;
}

function groupBy(items, key) {
  return items.reduce((groups, item) => {
    const value = item[key];
    (groups[value] = groups[value] || []).push(item);
    return groups;
  }, {});
}

function twoSum(nums, target) {
  const seen = new Map();
  for (let i = 0; i < nums.length; i++) {
    const complement = target - nums[i];
    if (seen.has(complement)) {
      return [seen.get(complement), i];
    }
    seen.set(nums[i], i);
  }
  return [];
}

function binarySearch(arr, target) {
  let low = 0;
  let high = arr.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (arr[mid] === target) {
      return mid;
    } else if (arr[mid] < target) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

function bubbleSort(arr) {
  const n = arr.length;
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n - i - 1; j++) {
      if (arr[j] > arr[j + 1]) {
        [arr[j], arr[j + 1]] = [arr[j + 1], arr[j]];
      }
    }
  }
  return arr;
}

function insertionSort(arr) {
  for (let i = 1; i < arr.length; i++) {
    const key = arr[i];
    let j = i - 1;
    while (j >= 0 && arr[j] > key) {
      arr[j + 1] = arr[j];
      j--;
    }
    arr[j + 1] = key;
  }
  return arr;
}

function mergeSort(arr) {
  if (arr.length <= 1) {
    return arr;
  }
  const mid = Math.floor(arr.length / 2);
  const left = mergeSort(arr.slice(0, mid));
  const right = mergeSort(arr.slice(mid));
  return merge(left, right);
}

function merge(left, right) {
  const result = [];
  let i = 0;
  let j = 0;
  while (i < left.length && j < right.length) {
    if (left[i] <= right[j]) {
      result.push(left[i++]);
    } else {
      result.push(right[j++]);
    }
  }
  return result.concat(left.slice(i)).concat(right.slice(j));
}

function quickSort(arr) {
  if (arr.length <= 1) {
    return arr;
  }
  const pivot = arr[arr.length - 1];
  const left = arr.filter((x, i) => x <= pivot && i < arr.length - 1);
  const right = arr.filter((x) => x > pivot);
  return [...quickSort(left), pivot, ...quickSort(right)];
}

function fizzBuzz(n) {
  for (let i = 1; i <= n; i++) {
    if (i % 15 === 0) {
      console.log("FizzBuzz");
    } else if (i % 3 === 0) {
      console.log("Fizz");
    } else if (i % 5 === 0) {
      console.log("Buzz");
    } else {
      console.log(i);
    }
  }
}

function debounce(fn, delay) {
  let timeout;
  return (...args) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}

function throttle(fn, limit) {
  let waiting = false;
  return (...args) => {
    if (!waiting) {
      fn(...args);
      waiting = true;
      setTimeout(() => {
        waiting = false;
      }, limit);
    }
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function formatDate(date) {
  return date.toISOString().split("T")[0];
}

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

function readFile(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function writeFile(filePath, content) {
  fs.writeFileSync(filePath, content, "utf8");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`);
  }
  return await response.json();
}

async function postJson(url, data) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`);
  }
  return await response.json();
}

async function loadUsers() {
  try {
    const users = await fetchJson("https://jsonplaceholder.typicode.com/users");
    for (const user of users) {
      console.log(`${user.id}: ${user.name}`);
    }
    return users;
  } catch (error) {
    console.error("Failed to load users:", error);
    return [];
  }
}

class Stack {
  constructor() {
    this.items = [];
  }

  push(item) {
    this.items.push(item);
  }

  pop() {
    return this.items.pop();
  }

  peek() {
    return this.items[this.items.length - 1];
  }

  isEmpty() {
    return this.items.length === 0;
  }

  get size() {
    return this.items.length;
  }
}

class Queue {
  constructor() {
    this.items = [];
  }

  enqueue(item) {
    this.items.push(item);
  }

  dequeue() {
    return this.items.shift();
  }

  isEmpty() {
    return this.items.length === 0;
  }
}

class Node {
  constructor(value) {
    this.value = value;
    this.next = null;
  }
}

class LinkedList {
  constructor() {
    this.head = null;
    this.length = 0;
  }

  append(value) {
    const node = new Node(value);
    if (!this.head) {
      this.head = node;
    } else {
      let current = this.head;
      while (current.next) {
        current = current.next;
      }
      current.next = node;
    }
    this.length++;
  }

  toArray() {
    const result = [];
    let current = this.head;
    while (current) {
      result.push(current.value);
      current = current.next;
    }
    return result;
  }
}

class Person {
  constructor(name, age) {
    this.name = name;
    this.age = age;
  }

  greet() {
    return `Hello, my name is ${this.name}`;
  }

  isAdult() {
    return this.age >= 18;
  }
}

class Animal {
  constructor(name) {
    this.name = name;
  }

  speak() {
    console.log(`${this.name} makes a sound.`);
  }
}

class Dog extends Animal {
  constructor(name, breed) {
    super(name);
    this.breed = breed;
  }

  speak() {
    console.log(`${this.name} barks.`);
  }
}

class EventEmitter {
  constructor() {
    this.listeners = {};
  }

  on(event, callback) {
    (this.listeners[event] = this.listeners[event] || []).push(callback);
  }

  emit(event, ...args) {
    (this.listeners[event] || []).forEach((callback) => callback(...args));
  }
}

const numbers = [5, 3, 8, 1, 9, 2];
const doubled = numbers.map((n) => n * 2);
const evens = numbers.filter((n) => n % 2 === 0);
const total = numbers.reduce((acc, n) => acc + n, 0);
const sorted = [...numbers].sort((a, b) => a - b);

for (let i = 0; i < numbers.length; i++) {
  console.log(numbers[i]);
}

for (const [index, value] of numbers.entries()) {
  console.log(`${index}: ${value}`);
}

const user = { name: "Ada", age: 36, email: "ada@example.com" };
for (const [key, value] of Object.entries(user)) {
  console.log(`${key}: ${value}`);
}

const { name, age } = user;
console.log(`${name} is ${age} years old`);

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ message: "Hello, world!" }));
});

server.listen(3000, () => {
  console.log("Server running on http://localhost:3000");
});

const express = require("express");
const app = express();
app.use(express.json());

app.get("/", (req, res) => {
  res.json({ message: "Hello, world!" });
});

app.get("/users/:id", (req, res) => {
  const { id } = req.params;
  res.json({ id });
});

app.post("/users", (req, res) => {
  const user = req.body;
  res.status(201).json(user);
});

app.listen(3000, () => {
  console.log("Listening on port 3000");
});

document.addEventListener("DOMContentLoaded", () => {
  const button = document.querySelector("#submit");
  const input = document.querySelector("#name");
  const output = document.getElementById("output");

  button.addEventListener("click", (event) => {
    event.preventDefault();
    output.textContent = `Hello, ${input.value}!`;
  });
});

function createElement(tag, className, text) {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  return element;
}

function renderList(items) {
  const list = document.createElement("ul");
  for (const item of items) {
    const li = document.createElement("li");
    li.textContent = item;
    list.appendChild(li);
  }
  document.body.appendChild(list);
}

module.exports = { fibonacci, factorial, isPrime, binarySearch, bubbleSort };
