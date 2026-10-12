import { useEffect, useState } from "react";

export interface User {
  id: number;
  name: string;
  email: string;
}

export interface Todo {
  id: number;
  title: string;
  completed: boolean;
}

export type Status = "idle" | "loading" | "success" | "error";

export function fibonacci(n: number): number {
  if (n <= 1) {
    return n;
  }
  return fibonacci(n - 1) + fibonacci(n - 2);
}

export function factorial(n: number): number {
  if (n === 0) {
    return 1;
  }
  return n * factorial(n - 1);
}

export function isPrime(n: number): boolean {
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

export function sum(numbers: number[]): number {
  return numbers.reduce((acc, n) => acc + n, 0);
}

export function average(numbers: number[]): number {
  if (numbers.length === 0) {
    return 0;
  }
  return sum(numbers) / numbers.length;
}

export function reverseString(str: string): string {
  return str.split("").reverse().join("");
}

export function isPalindrome(str: string): boolean {
  const cleaned = str.toLowerCase().replace(/[^a-z0-9]/g, "");
  return cleaned === cleaned.split("").reverse().join("");
}

export function unique<T>(items: T[]): T[] {
  return [...new Set(items)];
}

export function groupBy<T, K extends keyof T>(items: T[], key: K): Record<string, T[]> {
  return items.reduce((groups, item) => {
    const value = String(item[key]);
    (groups[value] = groups[value] || []).push(item);
    return groups;
  }, {} as Record<string, T[]>);
}

export function binarySearch(arr: number[], target: number): number {
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

export function bubbleSort(arr: number[]): number[] {
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

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function debounce<T extends (...args: any[]) => void>(fn: T, delay: number) {
  let timeout: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}

export async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error: ${response.status}`);
  }
  return (await response.json()) as T;
}

export async function getUsers(): Promise<User[]> {
  return fetchJson<User[]>("https://jsonplaceholder.typicode.com/users");
}

export class Stack<T> {
  private items: T[] = [];

  push(item: T): void {
    this.items.push(item);
  }

  pop(): T | undefined {
    return this.items.pop();
  }

  peek(): T | undefined {
    return this.items[this.items.length - 1];
  }

  isEmpty(): boolean {
    return this.items.length === 0;
  }

  get size(): number {
    return this.items.length;
  }
}

export class UserService {
  private users: User[] = [];

  add(user: User): void {
    this.users.push(user);
  }

  findById(id: number): User | undefined {
    return this.users.find((user) => user.id === id);
  }

  remove(id: number): void {
    this.users = this.users.filter((user) => user.id !== id);
  }

  getAll(): User[] {
    return [...this.users];
  }
}

export function useFetch<T>(url: string) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchJson<T>(url)
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch((err) => {
        if (!cancelled) setError(err);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [url]);

  return { data, loading, error };
}

export function Counter() {
  const [count, setCount] = useState(0);

  return (
    <div className="counter">
      <p>Count: {count}</p>
      <button onClick={() => setCount(count + 1)}>Increment</button>
      <button onClick={() => setCount(count - 1)}>Decrement</button>
    </div>
  );
}

export function TodoList({ todos }: { todos: Todo[] }) {
  return (
    <ul>
      {todos.map((todo) => (
        <li key={todo.id}>
          <input type="checkbox" checked={todo.completed} readOnly />
          {todo.title}
        </li>
      ))}
    </ul>
  );
}

export function UserList() {
  const { data: users, loading, error } = useFetch<User[]>("/api/users");

  if (loading) return <p>Loading...</p>;
  if (error) return <p>Error: {error.message}</p>;

  return (
    <ul>
      {users?.map((user) => (
        <li key={user.id}>
          {user.name} ({user.email})
        </li>
      ))}
    </ul>
  );
}
