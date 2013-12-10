require 'fileutils'
require 'digest'

class FileManager
  attr_accessor :files
  def initialize(client)
    @client = client
    @files = client.metainfo.files
    p @files
    createDirsAndFiles
    validateExisting
    @sum = 0
    for file in @files 
      @sum += file[1]
    end
  end

  def createDirsAndFiles
    dirName = @client.metainfo.torrentName + "/"
    FileUtils.makedirs dirName
    for file in @files 
      path, length = file
      if path.rindex("/").nil?
        FileUtils.touch(dirName+path)
        
      else
        FileUtils.makedirs(dirName+path[0..path.rindex("/")])
        FileUtils.touch(dirName+path)
        
      end
      file[0] = openFile(dirName+path)
    end
  end

  def validateExisting
    pieceLength = @client.metainfo.pieceLength
    @client.metainfo.pieces.each_with_index { |hash, index|
      data = read(index * pieceLength, pieceLength)
      if not (data.nil? or data.empty?)
        if Digest::SHA1.digest(data) == hash
          @client.pieces[index].verified=true
        end
      end
    }
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
      write(data, offset+lenToWrite)
    end
  end

  def close
    @files.each { |fd,len|
      fd.close
    }
  end

  def read(offset, length)
    lenCount = 0
    currIndex = 0
    while lenCount + @files[currIndex][1] <= offset do
      if lenCount + @files[currIndex][1] == @sum then # last file
        return ""
      end
      lenCount += @files[currIndex][1]
      currIndex += 1
    end
    newOffset = offset - lenCount

    fd, len = @files[currIndex]
    fd.seek(newOffset)
    if length + newOffset <= len then # writing all in this file
      data = fd.read(length)
      data = "" if data.nil?
    else
      lenToRead = len-newOffset
      data = fd.read(lenToRead) 
      data = "" if data.nil?
      length = length - lenToRead
      data.concat read(offset+lenToRead, length)
    end
    return data
  end

  def openFile(path)
    begin
      return File.open(path, "r+")
    rescue Errno::ENOENT
      return File.open(path, "w+")
    end
  end
end
