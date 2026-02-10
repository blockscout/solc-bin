package main

import (
	"bufio"
	"fmt"
	"os"
	"text/template"
	"time"

	"github.com/go-git/go-git/v5"
)

func shaFromVersion(ver string) string {
	return ver[len(ver)-8:]
}

func main() {
	versions, err := os.Open("scripts/push/version_list.txt")
	if err != nil {
		panic(err)
	}

	templateFile := "scripts/push/build.yml"
	tmpl, err := template.ParseFiles(templateFile)
	if err != nil {
		panic(err)
	}

	r, err := git.PlainOpen("./")
	if err != nil {
		panic(err)
	}

	w, err := r.Worktree()
	if err != nil {
		panic(err)
	}

	buildFileName := ".github/workflows/build.yml"
	scanner := bufio.NewScanner(versions)
	for scanner.Scan() {
		ver := scanner.Text()
		fmt.Println("pushing", ver)

		type Data struct {
			Version string
		}

		data := Data{
			Version: ver,
		}
		build, err := os.Create(buildFileName)
		if err != nil {
			panic(err)
		}
		if err := tmpl.Execute(build, data); err != nil {
			panic(err)
		}
		if _, err = w.Add(buildFileName); err != nil {
			panic(err)
		}
		if _, err = w.Commit(ver, &git.CommitOptions{}); err != nil {
			panic(err)
		}

		for i := 0; i < 5; i++ {
			if err = r.Push(&git.PushOptions{}); err == nil {
				break
			}
			time.Sleep(time.Second)
		}
		if err != nil {
			panic(err)
		}
	}
}
