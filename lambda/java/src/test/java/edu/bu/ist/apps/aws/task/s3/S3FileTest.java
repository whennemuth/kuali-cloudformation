package edu.bu.ist.apps.aws.task.s3;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.Matchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.io.BufferedInputStream;
import java.io.ByteArrayInputStream;
import java.util.List;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.invocation.InvocationOnMock;
import org.mockito.runners.MockitoJUnitRunner;
import org.mockito.stubbing.Answer;

import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.model.GetObjectRequest;
import com.amazonaws.services.s3.model.S3Object;
import com.amazonaws.services.s3.model.S3ObjectInputStream;

import edu.bu.ist.apps.aws.task.s3.S3File;
import edu.bu.ist.apps.aws.task.s3.S3FileParms;

@RunWith(MockitoJUnitRunner.class)
public class S3FileTest {

	@Mock private S3FileParms parms;
	@Mock private AmazonS3 s3Client;
	@Mock private S3Object s3Object;
	@Mock private S3ObjectInputStream s3InputStream;
	
	@Test
	/**
	 * A issue must be logged if parameters are incomplete
	 * @throws Exception
	 */
	public void test01Incomplete() throws Exception {		
		when(parms.isComplete()).thenReturn(false);		
		@SuppressWarnings("unused")
		S3File file = new S3File(parms);		
		verify(parms, times(1)).logIssue();
	}

	@Test
	/**
	 * Mock the InputStream of a file being downloaded from S3 and assert it is processed correctly.
	 */
	public void test02ProcessInputStream() throws Exception {
		String filecontent = "line1\nline2\nline3";
		final BufferedInputStream bis;
		
		bis = new BufferedInputStream(new ByteArrayInputStream(filecontent.getBytes()));		
		S3File file;
		
		try {
			/**
			 * For some reason using when...thenReturn() for mocking S3ObjectInputStream, the java runtime gets
			 * hosed and the CPU goes to 100%. So, using the alternative method doAnswer...when() with return value.
			 */
			doAnswer(new Answer<Integer>() {
				@Override
				public Integer answer(InvocationOnMock invocation) throws Throwable {
					return bis.read();
				}			
			}).when(s3InputStream).read();			
			doAnswer(new Answer<Integer>() {
				@Override
				public Integer answer(InvocationOnMock invocation) throws Throwable {
					return bis.available();
				}
			
			}).when(s3InputStream).available();			
			doAnswer(new Answer<Object>() {
				@Override
				public Object answer(InvocationOnMock invocation) throws Throwable {
					bis.close();
					return null;
				}			
			}).when(s3InputStream).close();
			
			when(s3Object.getObjectContent()).thenReturn(s3InputStream);
			when(s3Client.getObject(any(GetObjectRequest.class))).thenReturn(s3Object);
			when(parms.getS3Client()).thenReturn(s3Client);
			when(parms.isComplete()).thenReturn(true);
			when(parms.getBucketname()).thenReturn("mybucket");
			when(parms.getFilename()).thenReturn("myfilename");
			file = new S3File(parms);
		} 
		finally {
			if(bis != null)
				bis.close();
		}
		
		verify(parms, times(1)).logMessage("Downloading myfilename from S3 bucket mybucket...");
		
		List<String> lines = file.getLines();
		
		assertTrue(lines.size() == 3);
		assertEquals("line1", lines.get(0));
		assertEquals("line2", lines.get(1));
		assertEquals("line3", lines.get(2));
	}
}
