// Command kidzy runs the Kidzy media server: catalogue, ingest, API and the embedded admin.
package main

import (
	"fmt"
	"os"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "kidzy:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	_ = args
	fmt.Println("kidzy: nothing to serve yet")
	return nil
}
