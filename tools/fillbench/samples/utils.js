function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function sumOfSquares(numbers) {
  let total = 0;
  for (const n of numbers) {
    total += n * n;
  }
  return total;
}

function countChars(text) {
  const counts = {};
  for (const char of text) {
    counts[char] = (counts[char] || 0) + 1;
  }
  return counts;
}

function isSorted(arr) {
  for (let i = 1; i < arr.length; i++) {
    if (arr[i - 1] > arr[i]) {
      return false;
    }
  }
  return true;
}

class Counter {
  constructor() {
    this.count = 0;
  }

  increment() {
    this.count++;
  }

  reset() {
    this.count = 0;
  }
}

async function loadPosts() {
  const response = await fetch("/api/posts");
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`);
  }
  const posts = await response.json();
  return posts.filter((post) => post.published);
}

module.exports = { clamp, sumOfSquares, countChars, isSorted, Counter };
