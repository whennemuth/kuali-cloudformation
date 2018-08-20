package edu.bu.ist.apps.aws.task;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Map;

import edu.bu.ist.apps.aws.lambda.Logger;

public class TaskFactory {
	
	/**
	 * Get a Task enumeration that matches the supplied string.
	 * @param task
	 * @return
	 */
	public Task getTask(String task) {
		if(task == null)
			return Task.UNKNOWN;
		for(Task t : Task.values()) {
			if(t.getShortname().equalsIgnoreCase(task)) {
				return t;
			}
			if(t.name().equalsIgnoreCase(task)) {
				return t;
			}
		}
		return Task.UNKNOWN;
	}
	
	public Task extractTask(Object resourceProperties) {
		return extractTask(resourceProperties, null);
	}
	
	public Task extractTask(Object resourceProperties, Logger logger) {
		String value = extractValue(resourceProperties, "task", null);
		if(value == null)
			return Task.UNKNOWN;
		
		return getTask(value);
	}
	
	/**
	 * Get a value from an object. The object can be a map or a bean, so there are two ways to "extract" the value (key, or getter method). 
	 * @param resourceProperties
	 * @param logger
	 * @return
	 */
	public String extractValue(Object resourceProperties, String fieldname, Logger logger) {
		if(resourceProperties == null) {
			log(logger, "WARNING!: " + fieldname + " could not be found in null object");
			return null;
		}
		if(resourceProperties instanceof Map) {
			Map<?,?> map = (Map<?,?>) resourceProperties;
			if(map.get(fieldname) == null)
				return null;
			return String.valueOf(map.get(fieldname));
		}
		else {
			String value = tryAccessor(resourceProperties, fieldname);
			if(value == null) {
				log(logger, "WARNING!: " + fieldname + " could not be found.");
			}
		}		
		return null;
	}
	
	/**
	 * Invoke the accessor of an object identified by fieldname and return the value.
	 * @param obj
	 * @return
	 */
	private String tryAccessor(Object obj, String fieldname) {
		String task = null;
		Method getter = getMethod(obj, fieldname);
		if(getter != null) {
			try {
				task = (String) getter.invoke(obj);
			} 
			catch (IllegalAccessException | IllegalArgumentException | InvocationTargetException e) {
				// Do nothing
			}
		}
		return task;
	}
	
	/**
	 * Find a getter method for a field if it exists on an object.
	 * @param obj
	 * @return
	 */
	private Method getMethod(Object obj, String fieldname) {
		Method m = null;
		try {
			m = obj.getClass().getMethod(getAccessorName(fieldname));
		} 
		catch (NoSuchMethodException e) {
			// Do nothing;
		} 
		catch (SecurityException e) {
			// Do Nothing;
		}
		return m;
	}
	
	private String getAccessorName(String fieldname) {
		return "get" + fieldname.substring(0, 1).toUpperCase() + fieldname.substring(1);
	}
	
	private void log(Logger logger, String message) {
		if(logger == null)
			return;
		logger.log(message);
	}

}
