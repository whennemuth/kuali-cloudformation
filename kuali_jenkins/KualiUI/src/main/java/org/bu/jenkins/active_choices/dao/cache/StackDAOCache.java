package org.bu.jenkins.active_choices.dao.cache;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.active_choices.model.AbstractAwsResource;
import org.bu.jenkins.active_choices.model.CloudformationStack;

import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.StackSummary;

/**
 * Store the return values of api calls for stack resource and summary information so that repeat calls 
 * for the same or overlapping information need not be made. This is a primary performance optimization.
 * 
 * @author wrh
 *
 */
public class StackDAOCache extends BasicDAOCache {
	
	private Logger logger = LogManager.getLogger(StackDAOCache.class.getName());	
	private Map<String, CloudformationStack> cache = new HashMap<String, CloudformationStack>();	
	private boolean flushable = true;

	public boolean stacksSummariesAlreadyLoaded() {
		return alreadyLoaded(StackSummary.class);
	}
	public boolean stacksAlreadyLoaded() {
		return alreadyLoaded(Stack.class);
	}
	private boolean alreadyLoaded(Class<?> clazz) {
		EntryMessage m = logger.traceEntry("alreadyLoaded(clazz={})", clazz==null ? "null" : clazz.getName());
		boolean found = false;
		for(Entry<String, CloudformationStack> entry : cache.entrySet()) {
			if(clazz.equals(Stack.class) && ! entry.getValue().hasStack()) {
				logger.traceExit(m, "false");
				return false;
			}
			else if(clazz.equals(StackSummary.class) && ! entry.getValue().hasSummary()) {
				logger.traceExit(m, "false");
				return false;
			}
			found = true;
		}
		logger.traceExit(m, "true");
		return found;
	}
	
	public List<Stack> getStacks() {
		return getObjects(Stack.class);
	}
	
	public List<StackSummary> getSummaries() {
		return getObjects(StackSummary.class);
	}
	
	@SuppressWarnings("unchecked")
	private <T> List<T> getObjects(Class<T> clazz) {
		EntryMessage m = logger.traceEntry("getObjects(clazz={}", clazz==null ? "null" : clazz.getName());
		List<T> objs = new ArrayList<T>();
		for(Entry<String, CloudformationStack> entry : cache.entrySet()) {
			if(clazz.equals(Stack.class))
				objs.add((T) entry.getValue().getStack());
			if(clazz.equals(StackSummary.class))
				objs.add((T) entry.getValue().getStackSummary());
		}
		logger.traceExit(m, objs.size());
		return objs;
	}
	
	public void put(Object stackObj) {
		try {
			Method m = stackObj.getClass().getMethod("stackId");
			String stackId1 = (String) m.invoke(stackObj);
			if(cache.containsKey(stackId1)) {
				for(Entry<String, CloudformationStack> entry : cache.entrySet()) {
					String stackId2 = entry.getKey();
					if(stackId2.equals(stackId1)) {
						CloudformationStack cfstack = entry.getValue();
						logger.trace("Refreshing cache entry [{}]: {})", stackObj.getClass().getSimpleName(), stackId1);
						cfstack.put(stackObj);
						cache.put(stackId1, cfstack);
					}
				}
			}
			else {
				logger.trace("Adding cache entry [{}]: {})", stackObj.getClass().getSimpleName(), stackId1);
				cache.put(stackId1, new CloudformationStack().put(stackObj));
			}
		} 
		catch (NoSuchMethodException | SecurityException | InvocationTargetException | IllegalAccessException e) {
			e.printStackTrace();
		}
	}
	
	public void flush() {
		if(flushable) {
			cache.clear();
		}
	}

	public void setFlushable(boolean flushable) {
		this.flushable = flushable;
	}
	@Override
	protected void performCustomPreCachingAction(AbstractAwsResource resource, AbstractAwsResource cachedResource) {
		// Not implemented.
	}
	@Override
	protected Logger getLogger() {
		return logger;
	}
	
}
