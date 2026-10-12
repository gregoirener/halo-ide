# Expense tracker — half written on purpose.
#
# Let Halo finish it, top to bottom (each finished function helps the next):
#   1. Click at the very end of an empty function's docstring and press Enter.
#   2. Wait for the gray suggestion, then press Tab to accept it.
#   3. Do the same at the end of the last line of main().
# Then run it with ⌘R and type: add, 12.50, food, lunch, report, quit.

import json
import os

EXPENSES_FILE = "expenses.json"


def load_expenses():
    """Return the saved expenses as a list of dicts, or [] if there's no file yet."""
    if not os.path.exists(EXPENSES_FILE):
        return []
    with open(EXPENSES_FILE) as f:
        return json.load(f)


def save_expenses(expenses):
    """Write the list of expenses to EXPENSES_FILE as pretty-printed JSON."""


def add_expense(expenses, amount, category, note=""):
    """Append a new expense dict (amount, category, note) and save the list."""


def total_by_category(expenses):
    """Return a dict mapping each category to the sum of its amounts."""


def biggest_expense(expenses):
    """Return the expense with the largest amount, or None if there are none."""


def print_report(expenses):
    """Print each category's total, the grand total and the biggest expense."""
    totals = total_by_category(expenses)
    for category, total in sorted(totals.items()):
        print(f"  {category:<12} {total:>8.2f}")
    print(f"  {'total':<12} {sum(totals.values()):>8.2f}")
    biggest = biggest_expense(expenses)
    if biggest:
        print(f"  biggest: {biggest['amount']:.2f} on {biggest['category']}")


def main():
    expenses = load_expenses()
    while True:
        command = input("add / report / quit > ").strip().lower()
        if command == "quit":
            break
        elif command == "report":
            print_report(expenses)
        elif command == "add":
            amount = float(input("Amount: "))


if __name__ == "__main__":
    main()
