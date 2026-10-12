import json
import os

TASKS_FILE = "tasks.json"


def load_tasks():
    if not os.path.exists(TASKS_FILE):
        return []
    with open(TASKS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_tasks(tasks):
    with open(TASKS_FILE, "w", encoding="utf-8") as f:
        json.dump(tasks, f, indent=2)


def add_task(tasks, title):
    task = {"title": title, "done": False}
    tasks.append(task)
    save_tasks(tasks)
    return task


def complete_task(tasks, index):
    if 0 <= index < len(tasks):
        tasks[index]["done"] = True
        save_tasks(tasks)


def print_tasks(tasks):
    for i, task in enumerate(tasks):
        status = "x" if task["done"] else " "
        print(f"{i}. [{status}] {task['title']}")


def count_done(tasks):
    count = 0
    for task in tasks:
        if task["done"]:
            count += 1
    return count


def main():
    tasks = load_tasks()
    while True:
        command = input("> ").strip()
        if command == "quit":
            break
        elif command == "list":
            print_tasks(tasks)
        elif command.startswith("add "):
            add_task(tasks, command[4:])
        else:
            print("Unknown command")


if __name__ == "__main__":
    main()
