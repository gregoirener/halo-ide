import java.util.ArrayList;
import java.util.List;

public class Library {
    private final List<Book> books = new ArrayList<>();

    public void addBook(Book book) {
        books.add(book);
    }

    public Book findByTitle(String title) {
        for (Book book : books) {
            if (book.getTitle().equals(title)) {
                return book;
            }
        }
        return null;
    }

    public int countAvailable() {
        int count = 0;
        for (Book book : books) {
            if (book.isAvailable()) {
                count++;
            }
        }
        return count;
    }

    public static void main(String[] args) {
        Library library = new Library();
        library.addBook(new Book("Dune", "Frank Herbert"));
        library.addBook(new Book("Emma", "Jane Austen"));
        System.out.println("Available: " + library.countAvailable());
    }
}

class Book {
    private String title;
    private String author;
    private boolean available = true;

    public Book(String title, String author) {
        this.title = title;
        this.author = author;
    }

    public String getTitle() {
        return title;
    }

    public String getAuthor() {
        return author;
    }

    public boolean isAvailable() {
        return available;
    }
}
