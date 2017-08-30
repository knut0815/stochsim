#pragma once
#include "ComplexState.h"
#include <memory>
#include "types.h"

namespace stochsim
{
/// <summary>
/// A reaction which fires at a specific time (instead of having a propensity), with the time when the reaction fires next being determined by the properties of the first molecule of a ComplexState.
/// Since the first molecule of a complex state is also the oldest molecule, this type of reaction typically represents a reaction firing a fixed delay after a molecule of a given species was created.
/// </summary>
template<class T> class ComplexDelayedReaction : public DelayedReaction
{
public:
	/// <summary>
	/// Type definition of the function used to calculat the next firing time based on the properties of the first element represented by a ComplexState.
	/// </summary>
	typedef std::function<double(T& molecule)> FireTime;
	/// <summary>
	/// Type definition of the function which determines what should happen if the reaction fires.
	/// </summary>
	typedef std::function<void(T& molecule, SimInfo& simInfo)> FireAction;

	ComplexDelayedReaction(std::string name, std::shared_ptr<ComplexState<T>> state, FireTime fireTime, FireAction fireAction) : state_(state), fireTime_(fireTime), fireAction_(fireAction), name_(std::move(name))
	{

	}
	virtual double NextReactionTime() const override
	{
		return state_->Num() > 0 ? fireTime_(state_->Get(0)) : stochsim::inf;
	}
	virtual void Fire(SimInfo& simInfo) override
	{
		fireAction_(state_->Get(0), simInfo);
	}
	virtual std::string Name() const override
	{
		return name_;
	}
private:
	FireTime fireTime_;
	FireAction fireAction_;
	std::shared_ptr<ComplexState<T>> state_;
	const std::string name_;
};
}