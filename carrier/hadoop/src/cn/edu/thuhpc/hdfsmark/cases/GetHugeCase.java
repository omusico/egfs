package cn.edu.thuhpc.hdfsmark.cases;

import java.io.IOException;

import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.ini4j.Ini.Section;

public class GetHugeCase extends Configured implements TestCase{

	float size = 1;
	String src = null;
	String dst = null;
	
	@Override
	public String getDesc() {
		return "Get "+size+"GB File to Local "+dst+" from Hadoop";
	}

	@Override
	public void setup(Section sec) {
		size = Float.valueOf(sec.fetch("size"));
		src = sec.fetch("src");
		dst = sec.fetch("dst");
	}

	@Override
	public void run() {
		Path srcp = new Path(src);
	    Path dstp = new Path(dst);
	    
	    try {
			FileSystem dstFS = dstp.getFileSystem(getConf());
		    dstFS.copyToLocalFile(false, srcp, dstp);
		} catch (IOException e) {
			e.printStackTrace();
		}
		
	}

}
