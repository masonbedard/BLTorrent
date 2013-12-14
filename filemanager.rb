require 'fileutils'
require 'digest'

class FileManager
  attr_accessor :files
  def initialize(client)
    @client = client
    @files = client.metainfo.files

    createDirsAndFiles
    validateExisting
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
      while data.length > 0
        currIndex+=1
        fd, len = @files[currIndex]
        lenToWrite = [data.length, len].min 
        fd.seek(0)
        fd.write(data[0...lenToWrite])
        data=data[lenToWrite..data.length]
      end
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
      if currIndex = @files.length-1 then # last file
        return ""
      end
      lenCount += @files[currIndex][1]
      currIndex += 1
    end
    newOffset = offset - lenCount

    fd, len = @files[currIndex]
    fd.seek(newOffset)
    if length + newOffset <= len or currIndex == @files.length - 1 then # reading all in this file
      data = fd.read([length, len-newOffset].min)
      data = "" if data.nil?
      return data
    else #reading across multiple
      lenToRead = len-newOffset
      data = fd.read(lenToRead) 
      data = "" if data.nil?
      length = length - lenToRead
      while length > 0 
        currIndex += 1
        if currIndex = @files.length-1 then # last file
          return ""
        end
        fd, len = @files[currIndex]
        readLen = [length, len].min
        fd.seek(0)
        x = fd.read readLen
        x = "" if x.nil?
        data.concat x
        length = length - len
      end
      return data
    end
  end

  def openFile(path)
    begin
      return File.open(path, "r+")
    rescue Errno::ENOENT
      return File.open(path, "w+")
    end
  end
end
