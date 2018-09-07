package edu.bu.ist.apps.aws.lambda;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.mockito.Matchers.any;
import static org.mockito.Mockito.when;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.Before;
import org.junit.FixMethodOrder;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.runners.MockitoJUnitRunner;

import edu.bu.ist.apps.aws.task.Task;
import edu.bu.ist.apps.aws.task.TaskFactory;
import edu.bu.ist.apps.aws.task.TaskResult;
import edu.bu.ist.apps.aws.task.TaskRunner;

@FixMethodOrder
@RunWith(MockitoJUnitRunner.class)
public class ResponseDataTest {
	
	Map<String, Object> input = new HashMap<String, Object>();
	List<String> logs = new ArrayList<String>();
	
	@Mock TaskFactory taskFactory;
	@Mock TaskRunner taskRunner;
	@Mock TaskResult taskResult;
	ResponseDataParms parms;
	Logger logger = null;
	
	@Before
	public void setup() throws Exception {
		
		input.clear();
		logs.clear();
		
		Map<String, Object> map1 = new LinkedHashMap<String, Object>();
		Map<String, Object> map2 = new LinkedHashMap<String, Object>();
		Map<String, Object> map3 = new LinkedHashMap<String, Object>();
		
		// Gather values that are input intended as parameters for the lambda function. 
		map3.put("map3.key1", "map3.value1");
		map3.put("map3.key2", "map3.value2");
		map3.put("map3.key3", "map3.value3");		
		map2.put("map2.key1", "map2.value1");
		map2.put("map2.key2", "map2.value2");
		map2.put("map2.key3", map3);		
		map1.put("map1.key1", "map1.value1");
		map1.put("map1.key2", "map1.value2");
		map1.put("map1.key3", map2);				
		input.put("ResourceProperties", map1);
		
		// Gather values that are input and not intended for the lambda function. 
		input.put("apples", "oranges");
		input.put("this", "that");
		input.put("hello", "goodbye");
		
		// Mock the TaskResult
		LinkedHashMap<String, Object> results = new LinkedHashMap<String, Object>();
		results.put("result1", "myresult1");
		results.put("result2", "myresult2");
		results.put("result3", "myresult3");
		when(taskResult.isValid()).thenReturn(true);
		when(taskResult.getMaskedResults()).thenReturn(results);
		when(taskResult.getMaskedResultsForLogging()).thenReturn(results);
		
		// Mock the TaskRunner
		when(taskRunner.run(any(Task.class), any(Object.class))).thenReturn(taskResult);
		when(taskRunner.run(any(Task.class), any(Object.class), any(Logger.class))).thenReturn(taskResult);
		
		// Mock the TaskFactory
		when(taskFactory.getTask(any(String.class))).thenReturn(Task.CONTAINER_ENV_VARS);
		when(taskFactory.extractTask(any(Object.class))).thenReturn(Task.CONTAINER_ENV_VARS);
		when(taskFactory.extractTask(any(Object.class), any(Logger.class))).thenReturn(Task.CONTAINER_ENV_VARS);
		
		// Mock the ResponseDataParms
		logger = (String msg) -> { log(msg); };
		parms = new ResponseDataParms()
				.setInput(input)
				.setLogger(logger)
				.setTaskFactory(taskFactory)
				.setTaskRunner(taskRunner);
	}
	
	private void log(String msg) {
		System.out.println(msg);
		logs.add(msg);
	}
	
	private String getLogString() {
		StringBuilder s = new StringBuilder();
		for (Iterator<String> iterator = logs.iterator(); iterator.hasNext();) {
			String str = (String) iterator.next();
			s.append(str);
			if(iterator.hasNext()) {
				s.append("\r\n");
			}
		}
		return s.toString();
	}

	@Test
	public void test01NormalUsage() throws Exception {
		ResponseData rd = new ResponseData(parms);	
		
		// Assert the map content.
		assertEquals(4, rd.keySet().size());
		assertNotNull(rd.get("result1"));
		assertNotNull(rd.get("result2"));
		assertNotNull(rd.get("result3"));
		assertNotNull(rd.get("input"));
		
		// Assert what was logged when the map was being populated.		
		assertEquals( new String( 
				"-----------------------------------------\r\n" + 
				"   INPUT:\r\n" + 
				"-----------------------------------------\r\n" + 
				"input.apples: oranges\r\n" + 
				"input.hello: goodbye\r\n" + 
				"input.this: that\r\n" + 
				"input.ResourceProperties.map1.key1: map1.value1\r\n" + 
				"input.ResourceProperties.map1.key2: map1.value2\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key1: map2.value1\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key2: map2.value2\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key3.map3.key1: map3.value1\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key3.map3.key2: map3.value2\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key3.map3.key3: map3.value3\r\n" + 
				"-----------------------------------------\r\n" + 
				"   OUTPUT:\r\n" + 
				"-----------------------------------------\r\n" + 
				"result.result1: myresult1\r\n" + 
				"result.result2: myresult2\r\n" + 
				"result.result3: myresult3\r\n" +
				" "), getLogString());
	}

	@Test
	public void test02NoResourceData() throws Exception {

		input.remove("ResourceProperties");
		parms = parms.setInput(input);
		ResponseData rd = new ResponseData(parms);
		
		// Assert the map content.
		assertEquals(1, rd.keySet().size());
		assertNotNull(rd.get("input"));

		// Assert what was logged when the map was being populated.		
		assertEquals( new String( 
				"-----------------------------------------\r\n" + 
				"   INPUT:\r\n" + 
				"-----------------------------------------\r\n" + 
				"input.apples: oranges\r\n" + 
				"input.hello: goodbye\r\n" + 
				"input.this: that\r\n" + 
				"input.ResourceProperties: ERROR! No Resource Properties!\r\n" +
				" "), getLogString());
	}
	
	@Test
	public void test03InvalidResponseData() throws Exception {
		
		when(taskResult.isValid()).thenReturn(false);
		ResponseData rd = new ResponseData(parms);
		
		// Assert the map content.
		assertEquals(1, rd.keySet().size());
		assertNotNull(rd.get("input"));
		
		// Assert what was logged when the map was being populated.		
		assertEquals( new String( 
				"-----------------------------------------\r\n" + 
				"   INPUT:\r\n" + 
				"-----------------------------------------\r\n" + 
				"input.apples: oranges\r\n" + 
				"input.hello: goodbye\r\n" + 
				"input.this: that\r\n" + 
				"input.ResourceProperties.map1.key1: map1.value1\r\n" + 
				"input.ResourceProperties.map1.key2: map1.value2\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key1: map2.value1\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key2: map2.value2\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key3.map3.key1: map3.value1\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key3.map3.key2: map3.value2\r\n" + 
				"input.ResourceProperties.map1.key3.map2.key3.map3.key3: map3.value3\r\n" +
				" "), getLogString());
	}
}
