require 'fileutils'

class FileManager
  attr_accessor :files
  def initialize(files)
    @files = files

    createDirsAndFiles
  end

  def createDirsAndFiles
    for file in @files 
      path, length = file
      if path.rindex("/").nil?
        FileUtils.touch(path)
      else
        FileUtils.makedirs(path[0..path.rindex("/")])
        FileUtils.touch(path)
      end
      file[0] = File.open(path, "w")
    end
  end
  def write(data, offset)
    lenCount = 0
    currIndex = 0
    while lenCount + @files[currIndex][1] <= offset do
      lenCount += @files[currIndex][1]
      currIndex += 1
    end
    newOffset = offset - lenCount

    fd, len = @files[currIndex]
    fd.seek(newOffset)
    if data.length + newOffset <= len then # writing all in this file
      fd.write(data)
    else
      lenToWrite = len-newOffset
      fd.write(data[0...lenToWrite])
      data = data[len-newOffset..data.length]
      writeToFile(data, offset+lenToWrite)
    end
  end

  def close
    @files.each { |fd,len|
      fd.close
    }
  end
end