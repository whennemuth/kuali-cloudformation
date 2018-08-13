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
	
	public Task extractTask(Object obj) {
		return extractTask(obj, null);
	}
	
	/**
	 * Get a Task enumeration that matches a supplied string that must be accessed from within a map or as a getter of an object. 
	 * @param obj
	 * @param logger
	 * @return
	 */
	public Task extractTask(Object obj, Logger logger) {
		if(obj == null) {
			log(logger, "ERROR!: Task could not be found in null object");
			return Task.UNKNOWN;
		}
		if(obj instanceof Map) {
			Map<?,?> map = (Map<?,?>) obj;
			return getTask(String.valueOf(map.get("task")));
		}
		else {
			String task = tryGetTask(obj);
			if(task != null)
				return getTask(task);
		}
		log(logger, "ERROR!: Task could not be found.");
		return Task.UNKNOWN;
	}
	
	/**
	 * The task enumeration might be output by a "getTask" method of the supplied object.
	 * @param obj
	 * @return
	 */
	private String tryGetTask(Object obj) {
		String task = null;
		Method getter = getTaskMethod(obj);
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
	 * Find a getter method for a "task" field if it exists on an object.
	 * @param obj
	 * @return
	 */
	private Method getTaskMethod(Object obj) {
		Method m = null;
		try {
			m = obj.getClass().getMethod("getTask");
		} 
		catch (NoSuchMethodException e) {
			// Do nothing;
		} 
		catch (SecurityException e) {
			// Do Nothing;
		}
		return m;
	}
		
	private void log(Logger logger, String message) {
		if(logger == null)
			return;
		logger.log(message);
	}

}
