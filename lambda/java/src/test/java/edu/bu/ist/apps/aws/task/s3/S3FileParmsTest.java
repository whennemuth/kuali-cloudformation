package edu.bu.ist.apps.aws.task.s3;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import edu.bu.ist.apps.aws.task.s3.S3FileParms;

public class S3FileParmsTest {
	
	@Test
	public void test1() {
		S3FileParms p = new S3FileParms();		
		assertFalse(p.isComplete());
		assertEquals("S3FileParms missing required parameter(s): region, bucketname, filename, logger", p.getIssueMessage());
		assertNull(p.getS3Client());
		
		p = p.setRegion("myregion");
		assertFalse(p.isComplete());
		assertEquals("S3FileParms missing required parameter(s): bucketname, filename, logger", p.getIssueMessage());
		assertNull(p.getS3Client());
		
		p = p.setBucketname("mybucket");
		assertFalse(p.isComplete());
		assertEquals("S3FileParms missing required parameter(s): filename, logger", p.getIssueMessage());
		assertNull(p.getS3Client());
		
		p = p.setFilename("myfile");
		assertFalse(p.isComplete());
		assertEquals("S3FileParms missing required parameter(s): logger", p.getIssueMessage());
		assertNull(p.getS3Client());
		
		assertFalse(p.hasLogger());
		
		p = p.setLogger((String msg) -> System.out.println(msg));
		assertTrue(p.isComplete());
		assertNotNull(p.getS3Client());
		assertTrue(p.hasLogger());
		
		assertFalse(p.useProfile());
		
		p = p.setProfilename("myprofilename");
		assertTrue(p.isComplete());
		assertNotNull(p.getS3Client());
		assertTrue(p.useProfile());
	}

}
