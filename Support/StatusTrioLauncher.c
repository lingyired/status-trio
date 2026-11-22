// The Swift entry point lives in the embedded StatusTrioCore dylib.
extern void StatusTrioRunApplication(void);

int main(void) {
    StatusTrioRunApplication();
    return 0;
}
