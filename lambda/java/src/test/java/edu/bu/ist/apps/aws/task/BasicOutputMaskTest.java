package edu.bu.ist.apps.aws.task;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.List;

import org.junit.Before;
import org.junit.FixMethodOrder;
import org.junit.Test;
import org.junit.runners.MethodSorters;

@FixMethodOrder(MethodSorters.NAME_ASCENDING)
public class BasicOutputMaskTest {

	private List<String> logs = new ArrayList<String>();
	private static final String GOOD_CLASS = "edu.bu.ist.apps.aws.task.BasicOutputMask";
	
	@Before
	public void setup() {
		logs.clear();
	}

	private void assertLogMask(String json) {
		OutputMask mask = OutputMask.getInstance(json, (String msg) -> { log(msg); });

		assertTrue(mask instanceof BasicOutputMask);		
		assertNull(mask.getLogOutput(null, "Ooops!"));
		assertNull(mask.getLogOutput("key", null));
		
		assertEquals("*****", mask.getLogOutput("AWS_ACCESS_KEY_ID", "12345"));
		assertEquals("******", mask.getLogOutput("AWS_SECRET_ACCESS_KEY", "123456"));
		assertEquals("*******", mask.getLogOutput("MONGO_PASS", "1234567"));
		assertEquals("********", mask.getLogOutput("SERVICE_SECRET_1", "12345678"));
		
		assertEquals("12345", mask.getOutput("AWS_ACCESS_KEY_ID", "12345"));
		assertEquals("123456", mask.getOutput("AWS_SECRET_ACCESS_KEY", "123456"));
		assertEquals("1234567", mask.getOutput("MONGO_PASS", "1234567"));
		assertEquals("12345678", mask.getOutput("SERVICE_SECRET_1", "12345678"));
		
		assertNull(mask.getLogOutput("AWS_ACCESS_KEY_ID", null));
		assertNull(mask.getLogOutput("AWS_SECRET_ACCESS_KEY", null));
		assertNull(mask.getLogOutput("MONGO_PASS", null));
		assertNull(mask.getLogOutput("SERVICE_SECRET_1", null));
		
		assertNull(mask.getLogOutput("AWS_ACCESS_KEY_ID", ""));
		assertNull(mask.getLogOutput("AWS_SECRET_ACCESS_KEY", " "));
		assertNull(mask.getLogOutput("MONGO_PASS", "   "));
		assertNull(mask.getLogOutput("SERVICE_SECRET_1", "    "));
		
		assertEquals("apples", mask.getLogOutput("key1", "apples"));
		assertEquals("This and that", mask.getLogOutput("key1", "This and that"));
		assertEquals("abc123+_)", mask.getLogOutput("key1", "abc123+_)"));
	}
	
	private void assertFullMask(String json) {
		OutputMask mask = OutputMask.getInstance(json, (String msg) -> { log(msg); });

		assertTrue(mask instanceof BasicOutputMask);		
		assertNull(mask.getOutput(null, "Ooops!"));
		assertNull(mask.getOutput("key", null));
		
		assertEquals("*****", mask.getOutput("AWS_ACCESS_KEY_ID", "12345"));
		assertEquals("******", mask.getOutput("AWS_SECRET_ACCESS_KEY", "123456"));
		assertEquals("*******", mask.getOutput("MONGO_PASS", "1234567"));
		assertEquals("********", mask.getOutput("SERVICE_SECRET_1", "12345678"));
		assertEquals("random value", mask.getOutput("RANDOM_KEY", "random value"));

		// Logging output should be masked for fields under full masking, even though not present in logs masking.
		assertEquals("*****", mask.getLogOutput("AWS_ACCESS_KEY_ID", "12345"));
		assertEquals("******", mask.getLogOutput("AWS_SECRET_ACCESS_KEY", "123456"));
		assertEquals("*******", mask.getLogOutput("MONGO_PASS", "1234567"));
		assertEquals("********", mask.getLogOutput("SERVICE_SECRET_1", "12345678"));
		assertEquals("************", mask.getLogOutput("RANDOM_KEY", "random value"));

		assertNull(mask.getOutput("AWS_ACCESS_KEY_ID", null));
		assertNull(mask.getOutput("AWS_SECRET_ACCESS_KEY", null));
		assertNull(mask.getOutput("MONGO_PASS", null));
		assertNull(mask.getOutput("SERVICE_SECRET_1", null));
		
		assertNull(mask.getOutput("AWS_ACCESS_KEY_ID", ""));
		assertNull(mask.getOutput("AWS_SECRET_ACCESS_KEY", " "));
		assertNull(mask.getOutput("MONGO_PASS", "   "));
		assertNull(mask.getOutput("SERVICE_SECRET_1", "    "));		
	
	}
	
	private void assertNoMask(String json) {
		OutputMask mask = OutputMask.getInstance(json, (String msg) -> { log(msg); });

		assertTrue(mask instanceof BasicOutputMask);		
		assertNull(mask.getLogOutput(null, "Ooops!"));
		assertNull(mask.getLogOutput("key", null));
		
		assertEquals("12345", mask.getLogOutput("AWS_ACCESS_KEY_ID", "12345"));
		assertEquals("123456", mask.getLogOutput("AWS_SECRET_ACCESS_KEY", "123456"));
		assertEquals("1234567", mask.getLogOutput("MONGO_PASS", "1234567"));
		assertEquals("12345678", mask.getLogOutput("SERVICE_SECRET_1", "12345678"));
		
		assertEquals("12345", mask.getOutput("AWS_ACCESS_KEY_ID", "12345"));
		assertEquals("123456", mask.getOutput("AWS_SECRET_ACCESS_KEY", "123456"));
		assertEquals("1234567", mask.getOutput("MONGO_PASS", "1234567"));
		assertEquals("12345678", mask.getOutput("SERVICE_SECRET_1", "12345678"));	
	}
	
	private void assertMaskAll(String json, boolean allLog, boolean allFull) {
		OutputMask mask = OutputMask.getInstance(json, (String msg) -> { log(msg); });

		assertTrue(mask instanceof BasicOutputMask);		
		assertNull(mask.getLogOutput(null, "Ooops!"));
		assertNull(mask.getLogOutput("key", null));
		
		if(allFull) {
			assertEquals("***", mask.getLogOutput("anykey1", "123"));
			assertEquals("****", mask.getLogOutput("anykey2", "1234"));
			assertEquals("*****", mask.getLogOutput("anykey3", "12345"));
			
			assertEquals("***", mask.getOutput("anykey1", "123"));
			assertEquals("****", mask.getOutput("anykey2", "1234"));
			assertEquals("*****", mask.getOutput("anykey3", "12345"));
		}
		else if(allLog) {
			assertEquals("***", mask.getLogOutput("anykey1", "123"));
			assertEquals("****", mask.getLogOutput("anykey2", "1234"));
			assertEquals("*****", mask.getLogOutput("anykey3", "12345"));
			
			assertEquals("123", mask.getOutput("anykey1", "123"));
			assertEquals("1234", mask.getOutput("anykey2", "1234"));
			assertEquals("12345", mask.getOutput("anykey3", "12345"));			
		}
		else {
			assertEquals("123", mask.getLogOutput("anykey1", "123"));
			assertEquals("1234", mask.getLogOutput("anykey2", "1234"));
			assertEquals("12345*", mask.getLogOutput("anykey3", "12345"));
			
			assertEquals("123", mask.getOutput("anykey1", "123"));
			assertEquals("1234", mask.getOutput("anykey2", "1234"));
			assertEquals("12345", mask.getOutput("anykey3", "12345"));			
		}
	}

	@Test
	public void test01LogMask() {
		
		assertLogMask(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[],\r\n" + 
				"         logs:[  \r\n" + 
				"            \"AWS_ACCESS_KEY_ID\",\r\n" + 
				"            \"AWS_SECRET_ACCESS_KEY\",\r\n" + 
				"            \"MONGO_PASS\",\r\n" + 
				"            \"SERVICE_SECRET_1\"\r\n" + 
				"         ]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS));
		
		assertLogMask(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         logs:[  \r\n" + 
				"            \"AWS_ACCESS_KEY_ID\",\r\n" + 
				"            \"AWS_SECRET_ACCESS_KEY\",\r\n" + 
				"            \"MONGO_PASS\",\r\n" + 
				"            \"SERVICE_SECRET_1\"\r\n" + 
				"         ]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS));
	}
	
	@Test
	public void test02FullMask() {
		assertFullMask(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[  \r\n" + 
				"            \"AWS_ACCESS_KEY_ID\",\r\n" + 
				"            \"AWS_SECRET_ACCESS_KEY\",\r\n" + 
				"            \"MONGO_PASS\",\r\n" + 
				"            \"SERVICE_SECRET_1\"\r\n" + 
				"         ],\r\n" + 
				"         logs:[  \r\n" + 
				"            \"AWS_ACCESS_KEY_ID\",\r\n" + 
				"            \"RANDOM_KEY\"\r\n" + 
				"         ]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS));
	}
	
	@Test
	public void test03NoMask() {
		assertNoMask(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[],\r\n" + 
				"         logs:[]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS));
		
		assertNoMask(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{}\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS));
		
		assertNoMask(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{}\r\n" + 
				"}", GOOD_CLASS));
	}
	
	@Test 
	public void test04MaskAll() {
		assertMaskAll(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[all],\r\n" + 
				"         logs:[all]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), true, true);
		
		assertMaskAll(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[],\r\n" + 
				"         logs:[all]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), true, false);
		
		assertMaskAll(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[],\r\n" + 
				"         logs:[ALL]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), true, false);
		
		assertMaskAll(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[all],\r\n" + 
				"         logs:[]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), false, true);
	}

	private void log(String msg) {
		System.out.println(msg);
		logs.add(msg);
	}

}
