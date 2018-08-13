package edu.bu.ist.apps.aws.task;

import java.util.LinkedHashMap;
import java.util.Map;

import edu.bu.ist.apps.aws.lambda.Application;
import edu.bu.ist.apps.aws.lambda.Logger;

public class TaskRunner {

	private Task task;
	
	/** Restrict default constructor */
	@SuppressWarnings("unused")
	private TaskRunner() {
		super();
	}
	
	public TaskRunner(Task task) {
		this.task = task;
	}
	
	public TaskResult run(Object resourceProperties) {
		return run(resourceProperties, null);
	}
	
	public TaskResult run(Object resourceProperties, Logger logger) {
		TaskResult result = null;
		
		switch(task) {
			case CONTAINER_ENV_VARS:
				
				Application app = Application.extractApplication(resourceProperties, logger);
				
				switch(app) {
				case KC:
					break;
				case CORE:
					break;
				case COI:
					break;
				default:
					break;
				}
				
				Map<String, Object> map1 = new LinkedHashMap<String, Object>();
				Map<String, Object> map2 = new LinkedHashMap<String, Object>();
				Map<String, Object> map3 = new LinkedHashMap<String, Object>();
				
				map3.put("map3.key1", "map3.value1");
				map3.put("map3.key2", "map3.value2");
				map3.put("map3.key3", "map3.value3");
				
				map2.put("map2.key1", "map2.value1");
				map2.put("map2.key2", "map2.value2");
				map2.put("map2.key3", map3);
				
				map1.put("map1.key1", "map1.value1");
				map1.put("map1.key2", "map1.value2");
				map1.put("map1.key3", map2);
				
				result = new TaskResult(map1);
				
				break;
			case EC2_PUBLIC_KEYS:
				
				break;
			case UNKNOWN:
				
				break;
		}
		
		return result;
	}
	
}
