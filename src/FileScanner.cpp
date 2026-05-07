#include "FileScanner.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <dirent.h>
#include <string.h>
#include <algorithm>
#include <thread>
#include <mutex>
#include <queue>
#include <condition_variable>
#include <chrono>
#include <QtConcurrent>

struct linux_dirent64 {
    unsigned long long d_ino;
    long long          d_off;
    unsigned short     d_reclen;
    unsigned char      d_type;
    char               d_name[];
};

class InternalWorkQueue {
    std::queue<std::string> queue;
    std::mutex mutex;
    std::condition_variable cv;
    std::atomic<int> active_workers{0};
    bool stop = false;

public:
    void push(std::string path) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            queue.push(std::move(path));
        }
        cv.notify_one();
    }

    bool pop(std::string& path) {
        std::unique_lock<std::mutex> lock(mutex);
        cv.wait(lock, [this] { return !queue.empty() || stop; });
        if (stop && queue.empty()) return false;
        path = std::move(queue.front());
        queue.pop();
        active_workers++;
        return true;
    }

    void worker_done() {
        active_workers--;
        if (active_workers == 0 && queue.empty()) {
            {
                std::lock_guard<std::mutex> lock(mutex);
                stop = true;
            }
            cv.notify_all();
        }
    }
};

FileScanner::FileScanner(QObject *parent) : QObject(parent) {
    m_mediaExtensions = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".mp4", ".mkv", ".mov", ".avi", ".webm"};
}

void FileScanner::startScan(const QString &rootPath) {
    QtConcurrent::run([this, rootPath]() {
        runScan(rootPath.toStdString());
    });
}

void FileScanner::runScan(const std::string &rootPath) {
    auto start = std::chrono::high_resolution_clock::now();
    
    InternalWorkQueue wq;
    wq.push(rootPath);

    std::atomic<size_t> dirsScanned{0};
    std::mutex pathsMutex;
    QStringList foundPaths;
    
    int numThreads = std::thread::hardware_concurrency();
    std::vector<std::thread> workers;

    for (int i = 0; i < numThreads; ++i) {
        workers.emplace_back([this, &wq, &dirsScanned, &pathsMutex, &foundPaths]() {
            std::string path;
            while (wq.pop(path)) {
                int fd = open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
                if (fd != -1) {
                    dirsScanned++;
                    char buf[32768];
                    while (true) {
                        long nread = syscall(SYS_getdents64, fd, buf, sizeof(buf));
                        if (nread <= 0) break;

                        for (long bpos = 0; bpos < nread; ) {
                            struct linux_dirent64 *d = (struct linux_dirent64 *) (buf + bpos);
                            if (strcmp(d->d_name, ".") != 0 && strcmp(d->d_name, "..") != 0) {
                                if (d->d_type == DT_DIR) {
                                    wq.push(path + "/" + d->d_name);
                                } else if (d->d_type == DT_REG) {
                                    const char* dot = strrchr(d->d_name, '.');
                                    if (dot) {
                                        std::string ext = dot;
                                        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                                        if (m_mediaExtensions.count(ext)) {
                                            std::lock_guard<std::mutex> lock(pathsMutex);
                                            foundPaths.append(QString::fromStdString(path + "/" + d->d_name));
                                        }
                                    }
                                }
                            }
                            bpos += d->d_reclen;
                        }
                    }
                    close(fd);
                }
                wq.worker_done();
            }
        });
    }

    for (auto& t : workers) t.join();

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end - start;

    emit scanFinished(foundPaths, dirsScanned.load(), diff.count());
}
