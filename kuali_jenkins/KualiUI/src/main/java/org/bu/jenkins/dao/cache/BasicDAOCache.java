package org.bu.jenkins.dao.cache;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;

import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.mvc.model.AbstractAwsResource;

public abstract class BasicDAOCache {

	protected boolean flushable = true;
	protected Map<String, AbstractAwsResource> cache = new HashMap<String, AbstractAwsResource>();
	protected boolean loaded;

	public BasicDAOCache() {
		super();
	}

	public BasicDAOCache(BasicDAOCache other) {
		super();
		cache.putAll(other.cache);
	}
	
	/**
	 * Perform some action on the resource being cached, to be invoked just before adding it to the cache.
	 * @param resource
	 * @param cachedResource
	 */
	protected abstract void performCustomPreCachingAction(AbstractAwsResource resource, AbstractAwsResource cachedResource);
	
	protected abstract Logger getLogger();

	public void flush() {
		if(flushable) {
			cache.clear();
			loaded = false;
		}
	}

	public void setFlushable(boolean flushable) {
		this.flushable = flushable;
	}

	public BasicDAOCache remove(AbstractAwsResource instance) {
		cache.remove(instance.getArn());
		return this;
	}

	public AbstractAwsResource getItem(TestItem tester) {
		EntryMessage m = getLogger().traceEntry("getItem(tester={}", tester==null ? "null" : tester.hashCode());
		for(Entry<String, AbstractAwsResource> entry : cache.entrySet()) {
			if(tester.match(entry.getValue())) {
				getLogger().traceExit(m, entry.getKey());
				return entry.getValue();
			}
		}
		getLogger().traceExit(m, "null");
		return null;
	}

	public AbstractAwsResource get(String arn) {
		return cache.get(arn);
	}

	public Collection<AbstractAwsResource> getValues() {
		return cache.values();
	}

	public boolean alreadyLoaded() {
		return loaded;
	}
	
	public BasicDAOCache setLoaded(boolean loaded) {
		this.loaded = loaded;
		return this;
	}

	public void processAll(ProcessItem processor) {
		for(Entry<String, AbstractAwsResource> entry : cache.entrySet()) {
			processor.process(entry.getValue());
		}
	}
	
	private void prune(BasicDAOCache other) {
		this.cache.entrySet().removeAll(other.cache.entrySet());
	}
	
	public BasicDAOCache getPruned(BasicDAOCache other) {
		BasicDAOCache pruned = new BasicDAOCache(this) {
			@Override protected void performCustomPreCachingAction(AbstractAwsResource resource, AbstractAwsResource cachedResource) {
				// Unimplemented
			}
			@Override protected Logger getLogger() {
				return getLogger();
			}			
		};
		pruned.prune(other);
		return pruned;
	}

	public BasicDAOCache put(AbstractAwsResource resource) {
		EntryMessage m = getLogger().traceEntry("add(instance.getArn()={}", resource==null ? "null" : resource.getArn());
		if(resource == null) {
			return this;
		}
		AbstractAwsResource cached = cache.get(resource.getArn());
		if(cached == null) {
			cache.put(resource.getArn(), resource);
		}
		else {
			performCustomPreCachingAction(resource, cached);
			
			if(cached.getTags().size() < resource.getTags().size()) {
				cached.setTags(resource.getTags());
			}
			cache.put(cached.getArn(), cached);
		}		
		loaded = true;		
		getLogger().traceExit(m);
		return this;
	}

	public static interface TestItem {
		public boolean match(AbstractAwsResource resource);
	}

	public static interface ProcessItem {
		public void process(AbstractAwsResource resource);
	}

}