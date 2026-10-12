import { createServer } from "node:http";

interface Greeting {
  message: string;
  at: Date;
}

export function greet(name: string): Greeting {
  return { message: `Hello, ${name}!`, at: new Date() };
}

export function farewell(name: string): Greeting {
  return { message: `Goodbye, ${name}!`, at: new Date() };
}


export function wave( 
    return { message: }
)