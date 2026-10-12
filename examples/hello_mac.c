// hello_mac.c — a small native Mac program in one C file.
//
// Press ⌘R in Halo: clang compiles it and it runs in the terminal panel.
// It asks macOS what it's running on and draws a Mandelbrot set next to
// the answer. Drag the terminal panel taller if the picture is cut off.

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

enum { ROWS = 14, COLS = 41, MAX_ITER = 300 };

typedef struct { int r, g, b; } Color;

static int use_color;

/* ---------- What macOS says about this Mac ---------- */

static void sysctl_text(const char *name, char *out, size_t size) {
    if (sysctlbyname(name, out, &size, NULL, 0) != 0) snprintf(out, size, "unknown");
}

static long long sysctl_number(const char *name) {
    long long value = 0;               // the kernel fills 4 or 8 bytes
    size_t size = sizeof value;
    if (sysctlbyname(name, &value, &size, NULL, 0) != 0) return -1;
    return value;
}

static void describe_uptime(char *out, size_t size) {
    struct timeval boot;
    size_t len = sizeof boot;
    if (sysctlbyname("kern.boottime", &boot, &len, NULL, 0) != 0) { snprintf(out, size, "unknown"); return; }
    long minutes = (long)(time(NULL) - boot.tv_sec) / 60;
    long days = minutes / 1440, hours = minutes / 60 % 24;
    if (days > 0) snprintf(out, size, "%ld d %ld h %ld min", days, hours, minutes % 60);
    else snprintf(out, size, "%ld h %ld min", hours, minutes % 60);
}

static void describe_cores(char *out, size_t size) {
    long long total = sysctl_number("hw.ncpu");
    long long performance = sysctl_number("hw.perflevel0.physicalcpu");
    long long efficiency = sysctl_number("hw.perflevel1.physicalcpu");
    if (performance > 0 && efficiency > 0)
        snprintf(out, size, "%lld (%lld performance, %lld efficiency)", total, performance, efficiency);
    else
        snprintf(out, size, "%lld", total);   // Intel Macs have one kind of core
}

static void describe_disk(char *out, size_t size) {
    struct statfs disk;
    if (statfs("/", &disk) != 0) { snprintf(out, size, "unknown"); return; }
    double gb = 1e9;
    snprintf(out, size, "%.0f GB free of %.0f GB",
             (double)disk.f_bavail * disk.f_bsize / gb, (double)disk.f_blocks * disk.f_bsize / gb);
}

/* ---------- The Mandelbrot set ---------- */

// Smooth escape time for c = cx + cy·i, or -1 inside the set.
static double escape_time(double cx, double cy) {
    double x = 0, y = 0, x2 = 0, y2 = 0;
    int n = 0;
    while (x2 + y2 <= 256.0 && n < MAX_ITER) {
        y = 2 * x * y + cy;
        x = x2 - y2 + cx;
        x2 = x * x;
        y2 = y * y;
        n++;
    }
    if (n == MAX_ITER) return -1;
    return n + 1 - log2(0.5 * log(x2 + y2));   // fractional part removes the color bands
}

// Navy far away, through blue and sky to gold and white at the edge of the set.
static Color palette(double mu) {
    static const Color stops[] = {{9, 12, 30}, {28, 64, 140}, {96, 170, 235}, {236, 200, 120}, {255, 248, 230}};
    if (mu < 0) return (Color){4, 5, 12};
    double t = (1 - exp(-mu / 14.0)) * 4;      // 0…4 across the stops
    int i = (int)t;
    if (i >= 4) return stops[4];
    double f = t - i;
    return (Color){(int)(stops[i].r + f * (stops[i + 1].r - stops[i].r)),
                   (int)(stops[i].g + f * (stops[i + 1].g - stops[i].g)),
                   (int)(stops[i].b + f * (stops[i + 1].b - stops[i].b))};
}

static double image[ROWS * 2][COLS];   // two pixels per character cell (▀)

static void render(void) {
    for (int py = 0; py < ROWS * 2; py++)
        for (int px = 0; px < COLS; px++)
            image[py][px] = escape_time(-2.25 + 3.0 * (px + 0.5) / COLS, -1.05 + 2.1 * (py + 0.5) / (ROWS * 2));
}

static void print_image_row(int row) {
    if (!use_color) {   // plain text when the output isn't a terminal
        static const char ramp[] = "  ..::-=+*%";
        for (int px = 0; px < COLS; px++) {
            double mu = image[row * 2][px];
            putchar(mu < 0 ? '#' : ramp[(int)((1 - exp(-mu / 14.0)) * 10)]);
        }
        return;
    }
    for (int px = 0; px < COLS; px++) {
        Color top = palette(image[row * 2][px]), bottom = palette(image[row * 2 + 1][px]);
        printf("\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm▀", top.r, top.g, top.b, bottom.r, bottom.g, bottom.b);
    }
    printf("\x1b[0m");
}

/* ---------- Putting it together ---------- */

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

int main(void) {
    const char *term = getenv("TERM");
    use_color = isatty(STDOUT_FILENO) && !getenv("NO_COLOR") && !(term && strcmp(term, "dumb") == 0);

    char model[64], chip[128], version[32], build[32], cores[96], uptime[64], disk[64];
    char memory[32], load[48], rendered[48];
    sysctl_text("hw.model", model, sizeof model);
    sysctl_text("machdep.cpu.brand_string", chip, sizeof chip);
    sysctl_text("kern.osproductversion", version, sizeof version);
    sysctl_text("kern.osversion", build, sizeof build);
    describe_cores(cores, sizeof cores);
    describe_uptime(uptime, sizeof uptime);
    describe_disk(disk, sizeof disk);
    snprintf(memory, sizeof memory, "%lld GB", sysctl_number("hw.memsize") >> 30);
    double averages[3] = {0};
    getloadavg(averages, 3);
    snprintf(load, sizeof load, "%.2f  %.2f  %.2f", averages[0], averages[1], averages[2]);

    double start = now_ms();
    render();
    snprintf(rendered, sizeof rendered, "%d pixels in %.2f ms", COLS * ROWS * 2, now_ms() - start);

    char os[80];
    snprintf(os, sizeof os, "macOS %s (%s)", version, build);
    const char *labels[] = {"", "", "Mac", "Chip", "Cores", "Memory", "System", "Uptime", "Load", "Disk",
                            "Compiler", "Mandelbrot", "", ""};
    const char *values[] = {"Hello from C on your Mac", "", model, chip, cores, memory, os, uptime, load, disk,
                            "clang " __clang_version__, rendered, "", ""};

    // Side by side when the terminal is wide enough, stacked otherwise.
    struct winsize size;
    int width = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0 ? size.ws_col : 80;
    int side_by_side = width >= COLS + 3 + 52;

    for (int row = 0; row < ROWS || (!side_by_side && row < ROWS * 2); row++) {
        int info = side_by_side ? row : row - ROWS;
        if (!side_by_side && row >= ROWS && info > 1 && !labels[info][0] && !(info == ROWS - 1 && use_color)) continue;
        if (side_by_side || row < ROWS) {
            print_image_row(row);
            if (!side_by_side) { putchar('\n'); continue; }
            printf("   ");
        }
        if (info == 0) printf(use_color ? "\x1b[1m%s\x1b[0m" : "%s", values[0]);
        else if (info == 1) printf("────────────────────────");
        else if (info == ROWS - 1 && use_color)   // the palette, like a paint chart
            for (int i = 0; i < 8; i++) {
                Color c = palette(i * 5.0);
                printf("\x1b[48;2;%d;%d;%dm   \x1b[0m", c.r, c.g, c.b);
            }
        else if (labels[info][0])
            printf(use_color ? "\x1b[38;2;96;170;235m%-11s\x1b[0m %s" : "%-11s %s", labels[info], values[info]);
        putchar('\n');
    }
    return 0;
}
