import Foundation

/// Что из картинок доехало до бандла, считает `Tools/bundle-pictures.sh` —
/// один счёт на сборку и на выпуск. Портретов и фотографий в репозитории нет,
/// права на них не наши, и сборка без них соберётся молча: код возврата — это
/// и есть повод переспросить перед релизом.
func checkBundlePictures(_ t: Runner) {

    /// Бандл понарошку: нужны только папки с картинками.
    func bundle(philosophers: [String], statham: [String]?) -> String {
        let root = URL(fileURLWithPath: temporaryFile(named: "Fake.app", contents: ""))
        try? FileManager.default.removeItem(at: root)
        let resources = root.appendingPathComponent("Contents/Resources")

        func fill(_ directory: String, _ names: [String]) {
            let path = resources.appendingPathComponent(directory)
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            for name in names {
                try? Data().write(to: path.appendingPathComponent(name))
            }
        }
        fill("philosophers", philosophers)
        if let statham { fill("statham", statham) }
        return root.path
    }

    t.test("Картинки на месте — счёт и открытая дорога") {
        let run = runTool("bundle-pictures.sh",
                          bundle(philosophers: ["seneca.png", "sun-tzu.png"], statham: ["one.png"]))
        t.expect(run.status, 0)
        t.expect(run.printed.contains("портретов философов: 2"), true)
        t.expect(run.printed.contains("фотографий для режима Стетхема: 1"), true)
    }

    t.test("Пустая папка портретов — счёт ноль и повод переспросить") {
        let run = runTool("bundle-pictures.sh", bundle(philosophers: [], statham: ["one.png"]))
        t.expect(run.printed.contains("портретов философов: 0"), true)
        t.expect(run.printed.contains("философский режим покажет цитату без портрета"), true)
        t.expect(run.status, 2, "не отказ сборки, но и не молчание перед релизом")
    }

    t.test("Папки Стетхема нет вовсе — то же самое") {
        let run = runTool("bundle-pictures.sh", bundle(philosophers: ["seneca.png"], statham: nil))
        t.expect(run.printed.contains("фотографий для режима Стетхема: 0"), true)
        t.expect(run.printed.contains("режим Стетхема покажет наклейки без фигуры"), true)
        t.expect(run.status, 2)
    }

    t.test(".DS_Store портретом не считается") {
        // Иначе Finder, заглянувший в папку, сойдёт за положенную картинку.
        let run = runTool("bundle-pictures.sh", bundle(philosophers: [".DS_Store"], statham: ["one.png"]))
        t.expect(run.printed.contains("портретов философов: 0"), true)
        t.expect(run.status, 2)
    }

    t.test("Бандл надо назвать") {
        t.expect(runTool("bundle-pictures.sh").status, 1)
        t.expect(runTool("bundle-pictures.sh", missingPath()).status, 1, "нет такого бандла")
    }
}
