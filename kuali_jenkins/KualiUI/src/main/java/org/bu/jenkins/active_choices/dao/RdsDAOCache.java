package org.bu.jenkins.active_choices.dao;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.active_choices.model.RdsInstance;

/**
 * Store the return values of api calls for rds resource information so that repeat calls for the same or overlapping information need not be made.
 * This is a primary performance optimization.
 * 
 * @author wrh
 *
 */
public class RdsDAOCache {
	
	private Logger logger = LogManager.getLogger(RdsDAOCache.class.getName());

	private Map<String, RdsInstance> cache = new HashMap<String, RdsInstance>();	
	
	public boolean alreadyLoaded() {
		return cache.isEmpty() == false;
	}
	
	public RdsDAOCache add(RdsInstance instance) {
		EntryMessage m = logger.traceEntry("add(instance.getArn()={}", instance==null ? "null" : instance.getArn());
		RdsInstance cached = cache.get(instance.getArn());
		if(cached == null) {
			cache.put(instance.getArn(), instance);
		}
		else {
			if(cached.getSnapshots().size() < instance.getSnapshots().size()) {
				cached.setSnapshots(instance.getSnapshots());
			}
			if(cached.getTags().size() < instance.getTags().size()) {
				cached.setTags(instance.getTags());
			}
			cache.put(cached.getArn(), cached);
		}	
		
		logger.traceExit(m);
		return this;
	}

	public RdsDAOCache remove(RdsInstance instance) {
		cache.remove(instance.getArn());
		return this;
	}
	
	public void flush() {
		cache.clear();
	}
	
	public void processAll(ProcessItem processor) {
		for(Entry<String, RdsInstance> entry : cache.entrySet()) {
			processor.process(entry.getValue());
		}
	}
	
	public RdsInstance getItem(TestItem tester) {
		EntryMessage m = logger.traceEntry("getItem(tester={}", tester==null ? "null" : tester.hashCode());
		for(Entry<String, RdsInstance> entry : cache.entrySet()) {
			if(tester.match(entry.getValue())) {
				logger.traceExit(m, entry.getKey());
				return entry.getValue();
			}
		}
		logger.traceExit(m, "null");
		return null;
	}
	
	public static interface ProcessItem {
		public void process(RdsInstance instance);
	}
	
	public static interface TestItem {
		public boolean match(RdsInstance instance);
	}

	public RdsInstance get(String rdsArn) {
		return cache.get(rdsArn);
	}

	public void put(String arn, RdsInstance instance) {
		cache.put(arn, instance);
	}
	
	public Collection<RdsInstance> getValues() {
		return cache.values();
	}
}
