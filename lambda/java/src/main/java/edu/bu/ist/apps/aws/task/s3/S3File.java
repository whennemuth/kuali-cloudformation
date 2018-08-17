package edu.bu.ist.apps.aws.task.s3;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.model.GetObjectRequest;
import com.amazonaws.services.s3.model.S3Object;
import com.amazonaws.services.s3.model.S3ObjectInputStream;

/**
 * This class represents a single file stored in an S3 bucket.
 * Upon instantiation, the file is immediately downloaded from the bucket to a byte array.
 * Then the file can be sent to any OutputStream, ie: the local file system (FileOutputStream),
 * or printing out to the console (PrintStream), etc.
 * <p>
 * Similar example:
 * https://docs.aws.amazon.com/AmazonS3/latest/dev/RetrievingObjectUsingJava.html
 * <p>
 * Amazon API docs:
 * https://docs.aws.amazon.com/AWSJavaSDK/latest/javadoc/com/amazonaws/services/s3/AmazonS3.html
 * 
 * @author wrh
 *
 */
public class S3File {
	
	private S3FileParms parms;
	private byte[] bytes;
	
	/**
	 * Restrict default constructor
	 */
	@SuppressWarnings("unused")
	private S3File() {
		super();
	}

	/**
	 * Check the parameters are valid and download the file
	 * @param parms
	 */
	public S3File(S3FileParms parms) throws Exception {
		
		this.parms = parms;
		
		if(parms.isComplete()) {
			
			download();
			
			return;
		}
		
		parms.logIssue();
	}
	
	/**
	 * Download the file in the S3 bucket into a byte array.
	 * @throws Exception 
	 */
	private void download() throws Exception {
		
		S3Object s3obj = null;
		S3ObjectInputStream s3ObjInputStr = null;
		ByteArrayOutputStream baos = null;
		
		parms.logMessage("Downloading " + parms.getFilename() + " from S3 bucket " + parms.getBucketname() + "...");
		
		try {
			AmazonS3 s3Client = parms.getS3Client();
			s3obj = s3Client.getObject(new GetObjectRequest(parms.getBucketname(), parms.getFilename()));
			// Not wrapping in BufferedInputStream because S3ObjectInputStream cannot be mocked.
			// For some reason the mocked methods are not being called by wrapper. 
			s3ObjInputStr = s3obj.getObjectContent();		
			baos = new ByteArrayOutputStream();
			
			int reads = s3ObjInputStr.read();
			
			while(reads != -1){
				baos.write(reads);
				reads = s3ObjInputStr.read();
			}
			
			bytes = baos.toByteArray();
		} 
		catch (Exception e) {
			bytes = null;
			throw e;
		}
		finally {
			if(s3obj != null)
				s3obj.close();
			if(s3ObjInputStr != null)
				s3ObjInputStr.close();
			if(baos != null)
				baos.close();
		}
	}
	
	public void saveAs(File f) throws IOException {
		
		FileOutputStream fout = null;
		
		if(bytes == null || bytes.length == 0) {
			return;
		}
		try {
			fout = new FileOutputStream(f);
			print(fout);
		}
		finally {
			if(fout != null)
				fout.close();
		}
	}
	
	public void print() throws IOException {
		print(System.out);
	}
	
	public void print(OutputStream out) throws IOException {
		
		PrintWriter pw = null;
		BufferedReader reader = null;
		
		try {
			pw = new PrintWriter(out);
			reader = new BufferedReader(new InputStreamReader(new ByteArrayInputStream(bytes)));
			String line = null;
			while ((line = reader.readLine()) != null) {
	            pw.println(line);
	        }			
		} 
		finally {
			if(reader != null) {
				reader.close();
			}
			if(pw != null) {
				pw.close();
			}
		}
	}
	
	public List<String> getLines() throws IOException {
		
		BufferedReader reader = null;
		List<String> lines = new ArrayList<String>();
		
		try {
			reader = new BufferedReader(new InputStreamReader(new ByteArrayInputStream(bytes)));
			String line = null;
			while ((line = reader.readLine()) != null) {
	            lines.add(line);
	        }			
		} 
		finally {
			if(reader != null) {
				reader.close();
			}
		}
		
		return lines;
	}
	
	public byte[] getBytes() {
		return bytes;
	}

	public static void main(String[] args) throws Exception {
		
		S3File s3file = new S3File(new S3FileParms()
				.setRegion("us-east-1")
				.setBucketname("kuali-research-ec2-setup")
				.setFilename("qa/core/environment.variables.s3")
				.setProfilename("ecr.access")
				.setLogger((String msg) -> System.out.println(msg)));
		
		for(String line : s3file.getLines()) {
			System.out.println(line);
		}
	}
}
