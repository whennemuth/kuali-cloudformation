package edu.bu.ist.apps.aws.task;

import static org.junit.Assert.*;

import org.junit.runners.MethodSorters;

import java.util.ArrayList;
import java.util.List;

import org.junit.Before;
import org.junit.FixMethodOrder;
import org.junit.Test;

@FixMethodOrder(MethodSorters.NAME_ASCENDING)
public class OutputMaskTest {

	private List<String> logs = new ArrayList<String>();
	private static final String GOOD_CLASS = "edu.bu.ist.apps.aws.task.BasicOutputMask";
	
	@Before
	public void setup() {
		logs.clear();
	}
	
	@Test
	public void test01GetInstance() {
		
		OutputMask mask = OutputMask.getInstance(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[  \r\n" + 
				"\r\n" + 
				"         ],\r\n" + 
				"         logs:[  \r\n" + 
				"            \"AWS_ACCESS_KEY_ID\",\r\n" + 
				"            \"AWS_SECRET_ACCESS_KEY\",\r\n" + 
				"            \"MONGO_PASS\",\r\n" + 
				"            \"SERVICE_SECRET_1\"\r\n" + 
				"         ]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), (String msg) -> { log(msg); });
		
		assertTrue(mask instanceof BasicOutputMask);
		assertTrue(logs.isEmpty());
	}
	
	@Test
	public void test02GetInstanceNoQuotes() {
		OutputMask mask = OutputMask.getInstance(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[  \r\n" + 
				"\r\n" + 
				"         ],\r\n" + 
				"         logs:[  \r\n" + 
				"            AWS_ACCESS_KEY_ID,\r\n" + 
				"            AWS_SECRET_ACCESS_KEY,\r\n" + 
				"            MONGO_PASS,\r\n" + 
				"            SERVICE_SECRET_1\r\n" + 
				"         ]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), (String msg) -> { log(msg); });

		assertTrue(mask instanceof BasicOutputMask);
		assertTrue(logs.isEmpty());
	}
	
	@Test 
	public void test03GetInstanceBadJson() {
		OutputMask mask = OutputMask.getInstance("THIS IS NOT JSON", (String msg) -> { log(msg); });
		assertNull(mask);
		assertEquals(1, logs.size());
		assertTrue(logs.get(0).contains("JSONException"));		
	}

	@Test
	public void test04GetInstanceBadClass() {
		OutputMask mask = OutputMask.getInstance("{ class:edu.bu.ist.apps.aws.task.bogus }", (String msg) -> { log(msg); });
		assertNull(mask);
		assertEquals(1, logs.size());
		assertTrue(logs.get(0).contains("ClassNotFoundException"));
	}

	@Test
	public void test054GetInstanceNoParameters() {
		OutputMask mask = OutputMask.getInstance(String.format("{ class: %s }", GOOD_CLASS), (String msg) -> { log(msg); });
		assertNull(mask);
		assertEquals(1, logs.size());
		assertTrue(logs.get(0).contains("JSONException"));
	}

	@Test
	public void test06GetInstanceEmptyParameters() {
		OutputMask mask = OutputMask.getInstance(String.format("{ class: %s, parameters {} }", GOOD_CLASS), (String msg) -> { log(msg); });
		assertNull(mask);
		assertEquals(1, logs.size());
		assertTrue(logs.get(0).contains("JSONException"));
	}

	@Test
	public void test07GetInstanceEmptyParametersFields() {
		OutputMask mask = OutputMask.getInstance(String.format("{ "
				+ "class: %s, \n"
				+ "  parameters: { \n"
				+ "    full: [], \n"
				+ "    logs: [] \n"
				+ "  } \n"
				+ "}", GOOD_CLASS), (String msg) -> { log(msg); });
		assertNotNull(mask);
		assertTrue(logs.isEmpty());
	}
	
	private void log(String msg) {
		System.out.println(msg);
		logs.add(msg);
	}
}
